// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Ceilings on a scene's `sweep` animation, applied before a shared scene is
//! stored and broadcast. Decision 0043 explains why the server bounds it at
//! all: the client re-applies the same numbers, so a peer that never went
//! through this route still cannot exceed them.
//!
//! Everything else in a scene stays opaque to the server. Only a scene that
//! actually mentions `sweep` is parsed, and one that will not parse is passed
//! through untouched for the client to reject.

use serde_json::{Map, Value};

/// Animated ops one scene may carry; later ones lose their `sweep` and draw still.
pub const MAX_SWEEPS_PER_SCENE: usize = 8;
/// The longest a sweep may run, delay included.
pub const MAX_TIMELINE_SECONDS: f64 = 10.0;
const MIN_SWEEP_SECONDS: f64 = 0.1;
const MAX_DELTA: f64 = 10_000.0;
const DELTA_KEYS: [&str; 4] = ["dx", "dy", "dw", "dh"];
const ANIMATABLE_OPS: [&str; 4] = ["rect", "circle", "line", "text"];

/// Returns `scene` with every `sweep` inside the ceilings.
pub fn clamp_sweeps(scene: &str) -> String {
    if !scene.contains("\"sweep\"") {
        return scene.to_owned();
    }
    let Ok(mut value) = serde_json::from_str::<Value>(scene) else {
        return scene.to_owned();
    };
    let Some(ops) = value.get_mut("ops").and_then(Value::as_array_mut) else {
        return scene.to_owned();
    };
    let mut kept = 0;
    for op in ops.iter_mut().filter_map(Value::as_object_mut) {
        if !op.contains_key("sweep") {
            continue;
        }
        let animatable = op
            .get("op")
            .and_then(Value::as_str)
            .is_some_and(|kind| ANIMATABLE_OPS.contains(&kind));
        let bounded =
            animatable && kept < MAX_SWEEPS_PER_SCENE && op.get_mut("sweep").is_some_and(clamp_one);
        if bounded {
            kept += 1;
        } else {
            op.remove("sweep");
        }
    }
    serde_json::to_string(&value).unwrap_or_else(|_| scene.to_owned())
}

fn number(map: &Map<String, Value>, key: &str) -> f64 {
    map.get(key)
        .and_then(Value::as_f64)
        .filter(|n| n.is_finite())
        .unwrap_or(0.0)
}

/// False when the sweep is not an object, so the caller drops it.
fn clamp_one(sweep: &mut Value) -> bool {
    let Some(map) = sweep.as_object_mut() else {
        return false;
    };
    let delay = number(map, "delay").clamp(0.0, MAX_TIMELINE_SECONDS - MIN_SWEEP_SECONDS);
    let secs = number(map, "secs").clamp(MIN_SWEEP_SECONDS, MAX_TIMELINE_SECONDS - delay);
    for key in DELTA_KEYS {
        map.insert(
            key.into(),
            number(map, key).clamp(-MAX_DELTA, MAX_DELTA).into(),
        );
    }
    map.insert("delay".into(), delay.into());
    map.insert("secs".into(), secs.into());
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn run(scene: Value) -> Value {
        serde_json::from_str(&clamp_sweeps(&scene.to_string())).unwrap()
    }

    fn rect(sweep: Value) -> Value {
        json!({"op": "rect", "sweep": sweep})
    }

    #[test]
    fn a_scene_without_sweeps_is_returned_byte_for_byte() {
        let raw = r#"{ "ops": [], "state": "a b" }"#;
        assert_eq!(clamp_sweeps(raw), raw);
    }

    #[test]
    fn unparseable_text_passes_through() {
        assert_eq!(clamp_sweeps("\"sweep\" {"), "\"sweep\" {");
    }

    #[test]
    fn duration_and_delay_are_clamped_to_the_timeline() {
        let out = run(json!({"ops": [rect(json!({"secs": 3600, "delay": 5}))]}));
        let sweep = &out["ops"][0]["sweep"];
        assert_eq!(sweep["delay"], 5.0);
        assert_eq!(sweep["secs"], 5.0);
    }

    #[test]
    fn a_zero_or_missing_duration_gets_the_minimum() {
        let out = run(json!({"ops": [rect(json!({"secs": 0})), rect(json!({}))]}));
        assert_eq!(out["ops"][0]["sweep"]["secs"], 0.1);
        assert_eq!(out["ops"][1]["sweep"]["secs"], 0.1);
    }

    #[test]
    fn deltas_are_clamped_and_junk_becomes_zero() {
        let out = run(json!({"ops": [rect(json!({"secs": 1, "dx": 1e9, "dy": "far"}))]}));
        assert_eq!(out["ops"][0]["sweep"]["dx"], 10_000.0);
        assert_eq!(out["ops"][0]["sweep"]["dy"], 0.0);
    }

    #[test]
    fn only_the_first_eight_animated_ops_keep_their_sweep() {
        let ops: Vec<Value> = (0..12).map(|_| rect(json!({"secs": 1}))).collect();
        let out = run(json!({ "ops": ops }));
        let kept = out["ops"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|op| op.get("sweep").is_some())
            .count();
        assert_eq!(kept, MAX_SWEEPS_PER_SCENE);
    }

    #[test]
    fn a_sweep_on_a_non_animatable_op_or_of_the_wrong_shape_is_dropped() {
        let out = run(json!({"ops": [
            {"op": "cells", "sweep": {"secs": 1}},
            rect(json!("fast")),
        ]}));
        assert!(out["ops"][0].get("sweep").is_none());
        assert!(out["ops"][1].get("sweep").is_none());
    }
}
