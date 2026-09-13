use std::{collections::HashMap, env};
use teloxide::types::UserId;

pub struct Allowlist {
    users: HashMap<UserId, String>,
}

impl Allowlist {
    pub fn from_env() -> Self {
        let raw =
            env::var("ALLOWLIST").expect("ALLOWLIST env var not set - see mayak-bot/.env.example");

        let users = raw
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .map(|line| {
                let (id_str, username) = line.split_once(':').unwrap_or_else(|| {
                    panic!(
                        "malformed ALLOWLIST entry {line:?} - expected \"telegram_id:minecraft_username\""
                    )
                });

                let id: u64 = id_str.trim().parse().unwrap_or_else(|e| {
                    panic!("invalid Telegram ID {id_str:?} in ALLOWLIST: {e}")
                });

                (UserId(id), username.trim().to_string())
            })
            .collect();

        Self { users }
    }

    pub fn contains(&self, user_id: UserId) -> bool {
        self.users.contains_key(&user_id)
    }

    pub fn linked_username(&self, user_id: UserId) -> Option<&str> {
        self.users.get(&user_id).map(String::as_str)
    }
}
