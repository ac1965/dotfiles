# ① 英数字+記号 94種、20文字（最高エントロピー）
LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()-_=+[]{}|;:,.<>?' </dev/urandom | head -c 20; echo

# ② 英数字のみ 62種、20文字（記号NGの場合）
LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20; echo

# ③ 16進数 256種相当、32文字（スクリプト内部用）
openssl rand -hex 16
