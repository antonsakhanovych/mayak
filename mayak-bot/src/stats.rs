use serde::Deserialize;
use std::{collections::HashMap, fs, path::PathBuf};

use crate::bot::Metric;

pub struct StatsReader {
    data_dir: PathBuf,
}

#[derive(Deserialize)]
struct UserCacheEntry {
    name: String,
    uuid: String,
}

#[derive(Deserialize)]
struct StatsFile {
    stats: StatsCategories,
}

#[derive(Deserialize, Default)]
struct StatsCategories {
    #[serde(rename = "minecraft:custom", default)]
    custom: HashMap<String, u64>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum AdvancementEntry {
    Advancement { done: bool },
    Other(serde_json::Value),
}

pub struct PlayerCard {
    pub username: String,
    pub playtime_ticks: u64,
    pub deaths: u64,
    pub mob_kills: u64,
    pub advancements_done: usize,
}

impl StatsReader {
    pub fn new(data_dir: impl Into<PathBuf>) -> Self {
        Self {
            data_dir: data_dir.into(),
        }
    }

    fn usercache(&self) -> Vec<UserCacheEntry> {
        let path = self.data_dir.join("usercache.json");
        let raw = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
        serde_json::from_str(&raw)
            .unwrap_or_else(|e| panic!("failed to parse {}: {e}", path.display()))
    }

    pub fn resolve_uuid(&self, username: &str) -> Option<String> {
        self.usercache()
            .into_iter()
            .find(|entry| entry.name.eq_ignore_ascii_case(username))
            .map(|entry| entry.uuid)
    }

    fn read_stats(&self, uuid: &str) -> StatsCategories {
        let path = self
            .data_dir
            .join("world/players/stats")
            .join(format!("{uuid}.json"));
        fs::read_to_string(path)
            .ok()
            .and_then(|raw| serde_json::from_str::<StatsFile>(&raw).ok())
            .map(|file| file.stats)
            .unwrap_or_default()
    }

    fn count_advancements(&self, uuid: &str) -> usize {
        let path = self
            .data_dir
            .join("world/players/advancements")
            .join(format!("{uuid}.json"));
        let Ok(raw) = fs::read_to_string(path) else {
            return 0;
        };
        let Ok(entries) = serde_json::from_str::<HashMap<String, AdvancementEntry>>(&raw) else {
            return 0;
        };
        entries
            .values()
            .filter(|e| matches!(e, AdvancementEntry::Advancement { done: true }))
            .count()
    }

    pub fn player_card(&self, username: &str) -> Option<PlayerCard> {
        let uuid = self.resolve_uuid(username)?;
        let stats = self.read_stats(&uuid);
        Some(PlayerCard {
            username: username.to_string(),
            playtime_ticks: *stats.custom.get("minecraft:play_time").unwrap_or(&0),
            deaths: *stats.custom.get("minecraft:deaths").unwrap_or(&0),
            mob_kills: *stats.custom.get("minecraft:mob_kills").unwrap_or(&0),
            advancements_done: self.count_advancements(&uuid),
        })
    }

    pub fn leaderboard(&self, metric: Metric, limit: usize) -> Vec<(String, u64)> {
        let mut scores: Vec<(String, u64)> = self
            .usercache()
            .into_iter()
            .map(|entry| {
                let value = match metric {
                    Metric::Advancements => self.count_advancements(&entry.uuid) as u64,
                    Metric::Playtime => *self
                        .read_stats(&entry.uuid)
                        .custom
                        .get("minecraft:play_time")
                        .unwrap_or(&0),
                    Metric::Deaths => *self
                        .read_stats(&entry.uuid)
                        .custom
                        .get("minecraft:deaths")
                        .unwrap_or(&0),
                    Metric::Kills => *self
                        .read_stats(&entry.uuid)
                        .custom
                        .get("minecraft:mob_kills")
                        .unwrap_or(&0),
                };
                (entry.name, value)
            })
            .collect();
        scores.sort_by(|a, b| b.1.cmp(&a.1));
        scores.truncate(limit);
        scores
    }
}
