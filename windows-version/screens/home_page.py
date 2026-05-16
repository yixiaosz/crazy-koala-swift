from kivy.uix.boxlayout import BoxLayout
from kivy.uix.image import Image
from kivy.uix.label import Label
from kivy.graphics import Color, Rectangle
from screens.components import BaseScreen, InteractiveBoxLayout, RoundedButton, YellowBar

class HomePage(BaseScreen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # 设置主布局
        layout = BoxLayout(
            orientation="horizontal",
            spacing=50,
            padding=[100, 100, 100, 100],
        )

        # 设置背景颜色为白色
        with self.canvas.before:
            Color(1, 1, 1, 1)  # 白色背景
            self.bg = Rectangle(size=self.size, pos=self.pos)
            self.bind(size=self._update_bg, pos=self._update_bg)

        # 添加左侧图片
        img = Image(
            source="assets\door_close.png",
            allow_stretch=True,
            keep_ratio=True
        )
        layout.add_widget(img)

        text_layout = BoxLayout(orientation="vertical", spacing=5)

        # 主标题
        title_label = Label(
            text="Connect to our community\nTogether",
            font_size=72,
            color=(0, 0, 0, 1),
            halign="left",
            valign="bottom",
            size_hint=(1, 0.6),
            font_name="assets/fonts/Poppins/Poppins-ExtraBold.ttf"
        )
        title_label.bind(size=title_label.setter("text_size"))

        text_layout.add_widget(title_label)

        second_label = Label(
            text="For better future",
            font_size=48,
            color=(0, 0, 0, 1),
            halign="left",
            valign="top",
            size_hint=(1, 0.2),
            font_name="assets/fonts/Poppins/Poppins-LightItalic.ttf"
        )
        second_label.bind(size=second_label.setter("text_size"))

        text_layout.add_widget(second_label)

        start_button = RoundedButton(
            text="Press Koala Nose To Start",
            font_size=24,
            size_hint=(0.65, 0.1),
            custom_color=(0, 0, 0, 1),
            font_name="assets/fonts/Poppins/Poppins-Bold.ttf"
        )
        text_layout.add_widget(start_button)

        spacer = BoxLayout(size_hint=(1, 0.1))
        text_layout.add_widget(spacer)

        layout.add_widget(text_layout)


        layout.bind(on_touch_down=self.go_to_next_page)

        # 添加主布局到屏幕
        self.add_widget(layout)

    def _update_bg(self, *args):
        """动态更新背景大小和位置"""
        self.bg.size = self.size
        self.bg.pos = self.pos

    def go_to_next_page(self, instance, touch):
        """跳转到第二个页面"""
        self.manager.current = "choose_interact_type"


class ChooseInteractType(BaseScreen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Main layout: center everything vertically
        layout = BoxLayout(
            orientation="vertical",
            spacing=50,
        )

        title_bar = YellowBar(
            title_text="HOME PAGE",
        )
        layout.add_widget(title_bar)

         # Main layout: center everything vertically
        main_layout = BoxLayout(
            orientation="vertical",
            spacing=50,
            padding=[100, 50, 100, 10],
        )

        # First row: DEPOSIT and TAKE buttons
        first_row = BoxLayout(
            orientation="horizontal",
            spacing=100,
            size_hint=(1, 0.7),
        )
        deposit_layout = InteractiveBoxLayout(
            orientation="vertical",
            spacing=10,
            size_hint=(0.4, 1),
        )
        deposit_icon = Image(
            source="assets/deposit.png",
            allow_stretch=True,
            keep_ratio=True,
            size_hint=(1, 0.8),
        )
        deposit_label = Label(
            text="DEPOSIT",
            font_size=48,
            color=(0, 0, 0, 1),
            halign="center",
            valign="middle",
            size_hint=(1, 0.2),
            font_name="assets/fonts/Poppins/Poppins-Bold.ttf",
        )
        deposit_label.bind(size=deposit_label.setter("text_size"))
        deposit_layout.add_widget(deposit_icon)
        deposit_layout.add_widget(deposit_label)
        deposit_layout.bind(on_press=self.go_to_input_name_screen)
        first_row.add_widget(deposit_layout)
        
        take_layout = InteractiveBoxLayout(
            orientation="vertical",
            spacing=10,
            size_hint=(0.4, 1),
        )
        take_icon = Image(
            source="assets/take.png",
            allow_stretch=True,
            keep_ratio=True,
            size_hint=(1, 0.8),
        )
        take_label = Label(
            text="TAKE",
            font_size=48,
            color=(0, 0, 0, 1),
            halign="center",
            valign="middle",
            size_hint=(1, 0.2),
            font_name="assets/fonts/Poppins/Poppins-Bold.ttf",
        )
        take_label.bind(size=take_label.setter("text_size"))
        take_layout.add_widget(take_icon)
        take_layout.add_widget(take_label)
        take_layout.bind(on_press=self.go_to_select_take_screen)
        first_row.add_widget(take_layout)

        # Second row: Check happiness memories and End by pressing nose buttons
        second_row = BoxLayout(
            orientation="horizontal",
            spacing=100,
            size_hint=(1, 0.2),
        )

        # Happiness Memories button
        happiness_layout = InteractiveBoxLayout(
            orientation="horizontal",
            spacing=10,
            size_hint=(0.5, 1),
        )
        happiness_icon = Image(
            source="assets/happy.png",
            allow_stretch=True,
            keep_ratio=True,
            size_hint=(0.3, 1),
        )
        happiness_label = Label(
            text="HAPPY MEMORY",
            font_size=36,
            color=(0, 0, 0, 1),
            halign="center",
            valign="middle",
            size_hint=(0.7, 1),
            font_name="assets/fonts/Poppins/Poppins-Medium.ttf",
        )
        happiness_label.bind(size=happiness_label.setter("text_size"))
        happiness_layout.add_widget(happiness_icon)
        happiness_layout.add_widget(happiness_label)
        happiness_layout.bind(on_press=self.go_to_select_memeries)
        second_row.add_widget(happiness_layout)
        
        hint_layout = BoxLayout(
            orientation="horizontal",
            spacing=10,
            size_hint=(0.5, 1),
        )
        # 插入图片
        hint_image = Image(
            source="assets\simple_logo.png",
            allow_stretch=True,
            keep_ratio=True,
            size_hint=(0.2, 1),
        )
        hint_layout.add_widget(hint_image)

        # 添加提示文字
        hint_label = Label(
            text="End by pressing nose",
            font_size=36,
            color=(0, 0, 0, 1),
            halign="center",
            valign="middle",
            size_hint=(0.7, 1),
            font_name="assets/fonts/Poppins/Poppins-Medium.ttf"
        )
        hint_label.bind(size=hint_label.setter("text_size"))
        hint_layout.add_widget(hint_label)
        
        second_row.add_widget(hint_layout)

        # Add rows to the main layout
        main_layout.add_widget(first_row)
        main_layout.add_widget(second_row)
        layout.add_widget(main_layout)

        end_bar = YellowBar(
            title_text="",
        )
        layout.add_widget(end_bar)

        self.add_widget(layout)
        
    def go_to_input_name_screen(self, instance):
        """跳转到 InputNameScreen"""
        self.manager.switch_to("input_name_screen", mode="deposit")
    
    def go_to_select_take_screen(self, instance):
        """跳转到 SelectTakeItemScreen"""
        take_item_screen = self.manager.get_screen("select_take_screen")
        take_item_screen.load_items()
        self.manager.switch_to("select_take_screen", mode="take")
    
    def go_to_select_memeries(self, instance):
        """跳转到 Select memeries"""
        take_item_screen = self.manager.get_screen("happy_memories_screen")
        take_item_screen.load_items()
        self.manager.current = "happy_memories_screen"
