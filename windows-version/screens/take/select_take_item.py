from kivy.uix.gridlayout import GridLayout
from kivy.uix.label import Label
from kivy.uix.image import AsyncImage
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.scrollview import ScrollView
from database.db_operations import fetch_unretrieved_items, fetch_item_details
from screens.components import BaseScreen, YellowTitleBar
import os

class SelectTakeItemScreen(BaseScreen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        layout = BoxLayout(
            orientation="vertical",
            spacing=20,
        )

        # 创建主布局
        main_layout = BoxLayout(
            orientation="vertical",
            spacing=20,
            padding=[20, 20, 20, 20],
        )

        # 添加标题栏
        title_bar = YellowTitleBar(
            title_text="TAKE ITEM",
            button_text="BACK",
            on_button_press=self.go_back
        )
        layout.add_widget(title_bar)

        # 添加滚动区域
        scroll_view = ScrollView(size_hint=(1, 0.9))
        self.item_grid = GridLayout(cols=4, spacing=10, size_hint_y=None)
        self.item_grid.bind(minimum_height=self.item_grid.setter("height"))
        scroll_view.add_widget(self.item_grid)

        main_layout.add_widget(scroll_view)
        layout.add_widget(main_layout)
        self.add_widget(layout)

        # 加载物品
        self.load_items()

    def load_items(self):
        """加载所有未取走的物品"""
        self.item_grid.clear_widgets()
        items = fetch_unretrieved_items()
        total_items = len(items)
        cols = 4

        for name, photo_path in items:

            clickable_area = BoxLayout(
                orientation="vertical",
                size_hint_y=None,
                height=300,
                padding=(5, 5, 5, 5),
            )

            if photo_path and os.path.exists(photo_path):
                img = AsyncImage(
                    source=photo_path,
                    allow_stretch=True,
                    keep_ratio=True,
                    size_hint=(1, 0.8),
                )
            else:
                img = Label(
                    text="No Image",
                    size_hint=(1, 0.8),
                    color=(0, 0, 0, 1),
                    halign="center",
                    valign="middle",
                    font_name="assets/fonts/Poppins/Poppins-Medium.ttf"
                )
            clickable_area.add_widget(img)

            # 添加物品名称
            label = Label(
                text=name,
                font_size=24,
                color=(0, 0, 0, 1),
                size_hint=(1, 0.2),
                halign="center",
                valign="middle",
                font_name="assets/fonts/Poppins/Poppins-Medium.ttf"
            )
            label.bind(size=label.setter("text_size"))
            clickable_area.add_widget(label)

            # 为整个区域绑定点击事件
            clickable_area.bind(on_touch_down=lambda instance, touch, n=name: self.handle_touch(instance, touch, n))

            self.item_grid.add_widget(clickable_area)

        # 计算需要补充的空白占位符
        empty_slots = cols - (total_items % cols) if total_items % cols != 0 else 0
        for _ in range(empty_slots):
            empty_box = BoxLayout(size_hint_y=None, height=100)
            self.item_grid.add_widget(empty_box)

    def handle_touch(self, instance, touch, name):
        """处理点击事件"""
        if instance.collide_point(*touch.pos):
            print(f"Selected item: {name}")
            self.view_item(name)

    def view_item(self, name):
        """查看物品详情"""
        item = fetch_item_details(name)

        if item:
            self.manager.current_item = {
                "name": item["name"],
                "image_path": item["deposit_photo_path"],
                "audio_path": item["deposit_audio_path"],
                "deposit_time": item["deposit_created_at"]
            }
            print(f"Current item set: {self.manager.current_item}")
            self.manager.current = "view_deposit_info_screen"
        else:
            print(f"Item with name {name} not found!")

    def go_back(self, instance):
        """返回上一个界面"""
        self.manager.current = "choose_interact_type"
