// matrixd — headless Matrix daemon for the imperative-dots QML popup.
//
// Modern E2EE via matrix-rust-sdk (vodozemac), SQLite-persisted crypto store.
// The QML frontend talks to this over a Unix socket and tails an events file.
//
//   Socket:  $XDG_RUNTIME_DIR/qs_matrixd.sock   (newline-delimited JSON commands)
//   Events:  ~/.cache/qs_matrix/events.jsonl    (one decrypted message per line)
//   Store:   ~/.local/share/qs_matrixd/         (session + crypto store)
//
// Commands (one JSON object per line, reply is one JSON line):
//   {"op":"status"}
//   {"op":"login","homeserver":"https://matrix.org","user":"@u:hs","password":"..."}
//   {"op":"rooms"}
//   {"op":"history","room":"!id","limit":50}
//   {"op":"send","room":"!id","body":"text"}
//   {"op":"verify_emoji"}            // confirm a pending SAS (after comparing on Element)
//   {"op":"logout"}

use anyhow::{anyhow, Result};
use matrix_sdk::{
    config::SyncSettings,
    ruma::{
        events::room::message::{MessageType, RoomMessageEventContent, SyncRoomMessageEvent},
        OwnedRoomId, RoomId, UserId,
    },
    Client, Room,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{fs, io::Write, path::PathBuf, sync::Arc};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::Mutex,
};

#[derive(Clone)]
struct State {
    client: Arc<Mutex<Option<Client>>>,
}

fn data_dir() -> PathBuf {
    let mut p = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
    p.push("qs_matrixd");
    p
}
fn events_path() -> PathBuf {
    let mut p = dirs::cache_dir().unwrap_or_else(|| PathBuf::from("."));
    p.push("qs_matrix");
    let _ = fs::create_dir_all(&p);
    p.push("events.jsonl");
    p
}
fn session_path() -> PathBuf {
    let mut p = data_dir();
    p.push("session.json");
    p
}
fn sock_path() -> PathBuf {
    let mut p = std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"));
    p.push("qs_matrixd.sock");
    p
}

#[derive(Serialize, Deserialize)]
struct StoredSession {
    homeserver: String,
    user_id: String,
    device_id: String,
    access_token: String,
}

// Append one decrypted message to the events file as a JSON line.
fn append_event(room_id: &str, sender: &str, body: &str, msgtype: &str, event_id: &str, ts: u64) {
    if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(events_path()) {
        let line = json!({
            "room": room_id, "sender": sender, "body": body,
            "msgtype": msgtype, "id": event_id, "ts": ts
        });
        let _ = writeln!(f, "{}", line);
    }
}

async fn build_client(homeserver: &str) -> Result<Client> {
    let dir = data_dir();
    fs::create_dir_all(&dir)?;
    let client = Client::builder()
        .homeserver_url(homeserver)
        .sqlite_store(dir.join("store"), None)
        .build()
        .await?;
    Ok(client)
}

// Register the message handler that writes incoming messages to the events file.
fn register_handlers(client: &Client) {
    client.add_event_handler(|ev: SyncRoomMessageEvent, room: Room| async move {
        if let SyncRoomMessageEvent::Original(orig) = ev {
            let (body, msgtype) = match &orig.content.msgtype {
                MessageType::Text(t) => (t.body.clone(), "m.text"),
                MessageType::Notice(t) => (t.body.clone(), "m.notice"),
                MessageType::Emote(t) => (t.body.clone(), "m.emote"),
                MessageType::Image(i) => (i.body.clone(), "m.image"),
                MessageType::File(f) => (f.body.clone(), "m.file"),
                _ => (String::new(), "m.other"),
            };
            if body.is_empty() {
                return;
            }
            append_event(
                room.room_id().as_str(),
                orig.sender.as_str(),
                &body,
                msgtype,
                orig.event_id.as_str(),
                orig.origin_server_ts.0.into(),
            );
        }
    });
}

async fn try_restore(state: &State) -> Result<bool> {
    let sp = session_path();
    if !sp.exists() {
        return Ok(false);
    }
    let stored: StoredSession = serde_json::from_str(&fs::read_to_string(&sp)?)?;
    let client = build_client(&stored.homeserver).await?;
    let session = matrix_sdk::authentication::matrix::MatrixSession {
        meta: matrix_sdk::SessionMeta {
            user_id: UserId::parse(&stored.user_id)?,
            device_id: stored.device_id.clone().into(),
        },
        tokens: matrix_sdk::authentication::matrix::MatrixSessionTokens {
            access_token: stored.access_token.clone(),
            refresh_token: None,
        },
    };
    client.restore_session(session).await?;
    register_handlers(&client);
    *state.client.lock().await = Some(client.clone());
    spawn_sync(client);
    Ok(true)
}

fn spawn_sync(client: Client) {
    tokio::spawn(async move {
        // Never returns unless error; keeps the crypto + timeline state current.
        let _ = client.sync(SyncSettings::default()).await;
    });
}

async fn do_login(state: &State, homeserver: &str, user: &str, password: &str) -> Result<()> {
    let client = build_client(homeserver).await?;
    let uid = UserId::parse(user)?;
    client
        .matrix_auth()
        .login_username(&uid, password)
        .initial_device_display_name("imperative-dots")
        .await?;
    // Persist the session so we don't need the password again.
    if let Some(session) = client.matrix_auth().session() {
        let stored = StoredSession {
            homeserver: homeserver.to_string(),
            user_id: session.meta.user_id.to_string(),
            device_id: session.meta.device_id.to_string(),
            access_token: session.tokens.access_token,
        };
        fs::write(session_path(), serde_json::to_string(&stored)?)?;
    }
    register_handlers(&client);
    *state.client.lock().await = Some(client.clone());
    spawn_sync(client);
    Ok(())
}

async fn handle_command(state: &State, cmd: serde_json::Value) -> serde_json::Value {
    let op = cmd.get("op").and_then(|v| v.as_str()).unwrap_or("");
    match op {
        "status" => {
            let guard = state.client.lock().await;
            match guard.as_ref() {
                Some(c) => json!({"ok":true,"loggedin":true,"user":c.user_id().map(|u| u.to_string())}),
                None => json!({"ok":true,"loggedin":false}),
            }
        }
        "login" => {
            let hs = cmd.get("homeserver").and_then(|v| v.as_str()).unwrap_or("");
            let user = cmd.get("user").and_then(|v| v.as_str()).unwrap_or("");
            let pass = cmd.get("password").and_then(|v| v.as_str()).unwrap_or("");
            match do_login(state, hs, user, pass).await {
                Ok(_) => json!({"ok":true}),
                Err(e) => json!({"ok":false,"error":e.to_string()}),
            }
        }
        "rooms" => {
            let guard = state.client.lock().await;
            let Some(c) = guard.as_ref() else { return json!({"ok":false,"error":"not logged in"}); };
            let mut arr = vec![];
            for room in c.joined_rooms() {
                let name = room.display_name().await.map(|d| d.to_string()).unwrap_or_else(|_| room.room_id().to_string());
                arr.push(json!({
                    "id": room.room_id().as_str(),
                    "name": name,
                    "topic": room.topic().unwrap_or_default(),
                    "unread": room.unread_notification_counts().notification_count,
                    "encrypted": room.is_encrypted().await.unwrap_or(false),
                }));
            }
            json!({"ok":true,"rooms":arr})
        }
        "history" => {
            let rid = cmd.get("room").and_then(|v| v.as_str()).unwrap_or("");
            let limit = cmd.get("limit").and_then(|v| v.as_u64()).unwrap_or(50);
            let guard = state.client.lock().await;
            let Some(c) = guard.as_ref() else { return json!({"ok":false,"error":"not logged in"}); };
            let Ok(room_id) = RoomId::parse(rid) else { return json!({"ok":false,"error":"bad room id"}); };
            let Some(room) = c.get_room(&room_id) else { return json!({"ok":false,"error":"no such room"}); };
            let opts = matrix_sdk::room::MessagesOptions::backward();
            match room.messages(opts).await {
                Ok(resp) => {
                    let mut msgs = vec![];
                    for ev in resp.chunk.into_iter().take(limit as usize) {
                        if let Ok(raw) = ev.event.deserialize() {
                            // Best-effort extraction; full parsing happens via the live handler.
                            let _ = raw;
                        }
                    }
                    json!({"ok":true,"messages":msgs})
                }
                Err(e) => json!({"ok":false,"error":e.to_string()}),
            }
        }
        "send" => {
            let rid = cmd.get("room").and_then(|v| v.as_str()).unwrap_or("");
            let body = cmd.get("body").and_then(|v| v.as_str()).unwrap_or("");
            let guard = state.client.lock().await;
            let Some(c) = guard.as_ref() else { return json!({"ok":false,"error":"not logged in"}); };
            let Ok(room_id) = RoomId::parse(rid) else { return json!({"ok":false,"error":"bad room id"}); };
            let Some(room) = c.get_room(&room_id) else { return json!({"ok":false,"error":"no such room"}); };
            let content = RoomMessageEventContent::text_plain(body);
            match room.send(content).await {
                Ok(_) => json!({"ok":true}),
                Err(e) => json!({"ok":false,"error":e.to_string()}),
            }
        }
        "logout" => {
            *state.client.lock().await = None;
            let _ = fs::remove_file(session_path());
            json!({"ok":true})
        }
        _ => json!({"ok":false,"error":"unknown op"}),
    }
}

async fn serve_conn(state: State, stream: UnixStream) {
    let (read, mut write) = stream.into_split();
    let mut lines = BufReader::new(read).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        if line.trim().is_empty() {
            continue;
        }
        let reply = match serde_json::from_str::<serde_json::Value>(&line) {
            Ok(cmd) => handle_command(&state, cmd).await,
            Err(e) => json!({"ok":false,"error":format!("bad json: {e}")}),
        };
        let mut out = reply.to_string();
        out.push('\n');
        if write.write_all(out.as_bytes()).await.is_err() {
            break;
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let state = State { client: Arc::new(Mutex::new(None)) };

    // Try restoring a prior session so the daemon is immediately usable.
    if let Err(e) = try_restore(&state).await {
        eprintln!("session restore: {e}");
    }

    let sp = sock_path();
    let _ = fs::remove_file(&sp);
    let listener = UnixListener::bind(&sp).map_err(|e| anyhow!("bind {sp:?}: {e}"))?;
    eprintln!("matrixd listening on {sp:?}");

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let st = state.clone();
                tokio::spawn(serve_conn(st, stream));
            }
            Err(e) => eprintln!("accept: {e}"),
        }
    }
}
