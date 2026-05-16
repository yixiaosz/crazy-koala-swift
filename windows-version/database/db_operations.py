from .db_setup import get_connection
import os

# insert time
def insert_deposit(name, deposit_photo_path=None, deposit_audio_path=None):
    """插入物品的存储信息"""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        INSERT INTO items (name, deposit_photo_path, deposit_audio_path)
        VALUES (?, ?, ?)
    """, (name, deposit_photo_path, deposit_audio_path))

    conn.commit()
    conn.close()

def update_taken(item_name, taken_photo_path=None, taken_audio_path=None):
    """通过物品名称更新取走信息"""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        UPDATE items
        SET taken_photo_path = ?, 
            taken_audio_path = ?, 
            taken_created_at = CURRENT_TIMESTAMP
        WHERE name = ?
    """, (taken_photo_path, taken_audio_path, item_name))

    conn.commit()
    conn.close()
    print(f"Item with name {item_name} updated with taken photo and audio paths.")

def fetch_all_items():
    """
    获取包含存储和取走信息的所有物品，返回字典列表。
    """
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, name,
               deposit_photo_path, deposit_audio_path, deposit_created_at,
               taken_photo_path, taken_audio_path, taken_created_at
        FROM items
        WHERE deposit_photo_path IS NOT NULL 
          AND taken_photo_path IS NOT NULL
    """)
    rows = cursor.fetchall()
    conn.close()

    # 如果 rows 是空，返回空列表，避免后续报错
    if not rows:
        print("No items found in the database!")
        return []

    valid_items = []
    for row in rows:
        deposit_photo_path = row[2]
        taken_photo_path = row[5]
        
        # 检查路径是否存在且数据完整
        if deposit_photo_path and os.path.exists(deposit_photo_path) and taken_photo_path and os.path.exists(taken_photo_path):
            valid_items.append({
                "id": row[0],
                "name": row[1],
                "deposit_photo_path": deposit_photo_path,
                "deposit_audio_path": row[3],
                "deposit_created_at": row[4],
                "taken_photo_path": taken_photo_path,
                "taken_audio_path": row[6],
                "taken_created_at": row[7],
            })
        else:
            print(f"[DEBUG] Invalid or missing file for item: {row[1]} (ID: {row[0]})")

    return valid_items


def fetch_unretrieved_items():
    """
    获取所有存储但未被取走的物品信息。
    条件：taken_photo_path 和 taken_audio_path 均为空。
    """
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT name, deposit_photo_path
        FROM items
        WHERE taken_created_at IS NULL;
    """)
    items = cursor.fetchall()

    conn.close()
    valid_items = {}
    for name, photo in items:
        if photo and os.path.exists(photo):
            valid_items[name] = photo

    return list(valid_items.items())

def fetch_item_details(name):
    """根据名字从数据库中获取物品详情"""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT name, deposit_photo_path, deposit_audio_path, deposit_created_at
        FROM items
        WHERE name = ?
    """, (name,))
    item = cursor.fetchone()

    conn.close()

    if item:
        return {
            "name": item[0],
            "deposit_photo_path": item[1],
            "deposit_audio_path": item[2],
            "deposit_created_at": item[3]
        }
    return None


