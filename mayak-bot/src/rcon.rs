use rcon::Connection;
use tokio::{net::TcpStream, sync::Mutex};

pub struct RconClient {
    conn: Mutex<Connection<TcpStream>>,
}

impl RconClient {
    pub async fn connect(addr: &str, password: &str) -> rcon::Result<Self> {
        let conn = Connection::builder()
            .enable_minecraft_quirks(true)
            .connect(addr, password)
            .await?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    pub async fn execute(&self, command: &str) -> rcon::Result<String> {
        self.conn.lock().await.cmd(command).await
    }

    pub async fn say(&self, from_username: &str, message: &str) -> rcon::Result<()> {
        self.execute(&format!("say [{from_username}] {message}"))
            .await?;
        Ok(())
    }

    pub async fn list_online(&self) -> rcon::Result<Vec<String>> {
        let response = self.execute("list").await?;
        let names = response
            .split_once(':')
            .map(|(_, names)| names)
            .unwrap_or("")
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(String::from)
            .collect();
        Ok(names)
    }
}
