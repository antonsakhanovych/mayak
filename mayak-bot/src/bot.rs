use std::{str::FromStr, sync::Arc};

use teloxide::{
    Bot,
    macros::BotCommands,
    requests::{Requester, ResponseResult},
    types::{Message, User},
};

use crate::AppState;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Metric {
    Playtime,
    Deaths,
    Kills,
    Advancements,
}

impl FromStr for Metric {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_ascii_lowercase().as_str() {
            "playtime" => Ok(Metric::Playtime),
            "deaths" => Ok(Metric::Deaths),
            "kills" => Ok(Metric::Kills),
            "advancements" => Ok(Metric::Advancements),
            other => Err(format!(
                "unknown metric \"{other}\" - try playtime, deaths, kills, or advancements"
            )),
        }
    }
}

#[derive(BotCommands, Clone)]
#[command(rename_rule = "lowercase", description = "Commands:")]
pub enum Command {
    #[command(description = "server status and who's online")]
    Status,
    #[command(description = "a player's stats")]
    Player(String),
    #[command(
        description = "playtime|deaths|kills|advancements",
        parse_with = "split"
    )]
    Leaderboard(Metric),
    #[command(description = "send a message into the game chat")]
    Say(String),
}

pub async fn answer(
    bot: Bot,
    msg: Message,
    user: User,
    cmd: Command,
    app: Arc<AppState>,
) -> ResponseResult<()> {
    let reply = match cmd {
        Command::Status => match app.rcon.list_online().await {
            Ok(names) if names.is_empty() => "No one is online right now.".to_string(),
            Ok(names) => format!("Online now: {}", names.join(", ")),
            Err(e) => format!("Couldn't reach the server: {e}"),
        },

        Command::Player(username) => match app.stats.player_card(&username) {
            Some(card) => format!(
                "{}\nPlaytime: {:.1}h\nDeaths: {}\nMob kills: {}\nAdvancements: {}",
                card.username,
                card.playtime_ticks as f64 / 20.0 / 3600.0,
                card.deaths,
                card.mob_kills,
                card.advancements_done,
            ),
            None => format!("No data for \"{username}\" - check the spelling?"),
        },

        Command::Leaderboard(metric) => {
            let rows = app.stats.leaderboard(metric, 5);
            if rows.is_empty() {
                "No data yet.".to_string()
            } else {
                rows.iter()
                    .enumerate()
                    .map(|(i, (name, score))| format!("{}. {name}: {score}", i + 1))
                    .collect::<Vec<_>>()
                    .join("\n")
            }
        }

        Command::Say(text) => {
            let username = app
                .allowlist
                .linked_username(user.id)
                .expect("checked by the allowlist filter upstream");
            match app.rcon.say(username, &text).await {
                Ok(()) => "sent".to_string(),
                Err(e) => format!("failed to send: {e}"),
            }
        }
    };

    bot.send_message(msg.chat.id, reply).await?;
    Ok(())
}
