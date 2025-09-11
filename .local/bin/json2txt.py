#!/usr/bin/env python3
import json
import sys
from datetime import datetime


def load_json(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        return json.load(f)


def extract_text(conversations):
    lines = []
    for conv in conversations:
        title = conv.get("title", "Untitled")
        create_time = conv.get("create_time", 0)
        dt_str = (
            datetime.fromtimestamp(create_time).strftime("%Y-%m-%d %H:%M")
            if create_time
            else "No Date"
        )
        lines.append(f"=== Conversation: {dt_str} ({title}) ===")

        mapping = conv.get("mapping", {})
        ordered = sorted(mapping.items(), key=lambda kv: kv[1].get("create_time", 0))

        for _, val in ordered:
            msg = val.get("message")
            if not msg:
                continue
            role = msg.get("author", {}).get("role", "system").capitalize()
            parts = msg.get("content", {}).get("parts", [])
            if not parts:
                continue

            part = parts[0]
            if isinstance(part, str):
                content = part.strip()
            else:
                content = json.dumps(part, ensure_ascii=False)

            lines.append(f"{role}: {content}\n")
    return lines


def main():
    if len(sys.argv) != 2:
        print("Usage: python json2txt.py conversations.json")
        sys.exit(1)

    file_path = sys.argv[1]
    conversations = load_json(file_path)

    if not isinstance(conversations, list):
        print("❌ エラー: conversations.json はリスト形式ではありません。")
        sys.exit(1)

    text_lines = extract_text(conversations)

    output_file = "chat_export.txt"
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("\n".join(text_lines))

    print(f"✅ テキスト化完了: {output_file}")


if __name__ == "__main__":
    main()
