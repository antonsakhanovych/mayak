use std::sync::Arc;

use teloxide::{
    Bot,
    dispatching::UpdateFilterExt,
    prelude::*,
    types::{Message, Update, User},
    utils::command::BotCommands,
};

use crate::{
    allowlist::Allowlist,
    bot::{Command, answer},
    rcon::RconClient,
    stats::StatsReader,
};

mod allowlist;
mod bot;
mod rcon;
mod stats;

pub struct AppState {
    pub stats: StatsReader,
    pub rcon: RconClient,
    pub allowlist: Allowlist,
}

impl AppState {
    pub async fn from_env() -> Self {
        let allowlist = Allowlist::from_env();
        let stats = StatsReader::new("/data");

        let rcon_host = std::env::var("RCON_HOST").unwrap_or_else(|_| "server".to_string());
        let rcon_port = std::env::var("RCON_PORT").unwrap_or_else(|_| "25575".to_string());
        let rcon_password = std::env::var("RCON_PASSWORD").expect("RCON_PASSWORD env var not set");
        let rcon = RconClient::connect(&format!("{rcon_host}:{rcon_port}"), &rcon_password)
            .await
            .expect("failed to connect to RCON");

        Self {
            stats,
            rcon,
            allowlist,
        }
    }
}

#[tokio::main]
async fn main() {
    let app = Arc::new(AppState::from_env().await);
    let bot = Bot::from_env();
    bot.set_my_commands(Command::bot_commands())
        .await
        .expect("failed to register commands with Telegram");

    let schema = Update::filter_message()
        .filter_map(|msg: Message| msg.from.clone())
        .filter(|user: User, app: Arc<AppState>| app.allowlist.contains(user.id))
        .filter_command::<Command>()
        .endpoint(answer);

    Dispatcher::builder(bot, schema)
        .dependencies(dptree::deps![app])
        .build()
        .dispatch()
        .await;
}
