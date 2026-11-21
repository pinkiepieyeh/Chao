class_name EasterEggs
extends RefCounted
## Time-limited jokes, switched on and off from release/events.json in the repository (fetched with the update manifest),
## so the maintainer can end one early by pushing a change. Display only: rules, hashes and saved data never change.
##   meow: cards whose current revision was submitted on `date` (Beijing time) show 喵 before every punctuation mark,
##         until `until_unix` or until `enabled` is turned off.

const PUNCTUATION := "，。！？、；：…—（）《》【】「」『』“”‘’,.!?;:()[]~～"
const BEIJING_OFFSET := 8 * 3600

static var config: Dictionary = {}

static func configure(raw: Variant) -> void:
	config = {}
	if not raw is Dictionary or not raw.get("meow") is Dictionary: return
	var meow_config: Dictionary = raw.meow
	if not meow_config.get("enabled") is bool or not meow_config.get("date") is String: return
	if not (meow_config.get("until_unix") is float or meow_config.get("until_unix") is int): return
	if RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(meow_config.date) == null: return
	config = {"meow": {"enabled": meow_config.enabled, "date": meow_config.date, "until_unix": int(meow_config.until_unix)}}

static func meow_active(now: float = -1.0) -> bool:
	var meow_config: Dictionary = config.get("meow", {})
	if meow_config.is_empty() or not meow_config.enabled: return false
	return (Time.get_unix_time_from_system() if now < 0.0 else now) < float(meow_config.until_unix)

## The Beijing calendar date of an ISO time stamp, e.g. "2026-11-20T17:00:00.000Z" -> "2026-11-21".
static func beijing_date(stamp: String) -> String:
	if stamp.length() < 19: return ""
	var unix := Time.get_unix_time_from_datetime_string(stamp.left(19))
	return Time.get_date_string_from_unix_time(unix + BEIJING_OFFSET)

## A catalog record's submission date: when its current revision was accepted, else when the card was first added.
static func record_date(record: Dictionary) -> String:
	return beijing_date(str(record.get("submitted_at", record.get("created_at", ""))))

static func meow_date(date: String) -> bool:
	return not date.is_empty() and meow_active() and date == str(config.get("meow", {}).get("date", ""))

## Puts 喵 before every punctuation mark; a decimal point between digits is left alone.
static func meow(text: String) -> String:
	var result := ""
	for i in text.length():
		var character := text[i]
		var decimal := character == "." and i > 0 and i + 1 < text.length() and text[i - 1].is_valid_int() and text[i + 1].is_valid_int()
		if PUNCTUATION.contains(character) and not decimal and not (i > 0 and text[i - 1] == "喵"): result += "喵"
		result += character
	return result

## A display definition marked for the meow egg: its name now, its rules text when the card face lays it out.
static func meow_definition(definition: Dictionary) -> Dictionary:
	var marked := definition.duplicate(true)
	marked["name"] = meow(str(marked.get("name", "")))
	marked["_meow"] = true
	return marked
