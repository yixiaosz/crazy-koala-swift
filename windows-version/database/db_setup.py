import sqlite3

DB_NAME = "items.db"

def get_connection():
    """获取数据库连接"""
    return sqlite3.connect(DB_NAME)

def initialize_database():
    """初始化数据库并创建表"""
    conn = get_connection()
    cursor = conn.cursor()

    # 创建物品表
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='items';")
    table_exists = cursor.fetchone()

    if not table_exists:
        # 创建物品表
        cursor.execute("""
            CREATE TABLE items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,

                deposit_photo_path TEXT,
                deposit_audio_path TEXT,
                deposit_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

                taken_photo_path TEXT,
                taken_audio_path TEXT,
                taken_created_at TIMESTAMP
            );
        """)
        print("Database initialized: table 'items' created.")
    else:
        print("Database already initialized.")

    conn.commit()
    conn.close()
