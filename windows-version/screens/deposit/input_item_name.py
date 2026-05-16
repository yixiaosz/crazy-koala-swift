from kivy.uix.textinput import TextInput
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.button import Button
from screens.components import BaseScreen, RoundedButton, YellowBar
from kivy.uix.gridlayout import GridLayout
import os

class CustomKeyboard(BoxLayout):
    def __init__(self, target_input, **kwargs):
        super().__init__(orientation="vertical", **kwargs)
        self.target_input = target_input
        self.is_caps = False

        self.layout = [
            "1234567890",
            "qwertyuiop",
            "asdfghjkl",
            "zxcvbnm",
            ",.!?;:'\"@_-[]&",
        ]

        self.create_keyboard()

    def create_keyboard(self):
        """创建键盘布局"""

        keyboard_layout = GridLayout(
            cols=10,
            spacing=2,
            size_hint=(1, None),
            height=300,
        )
        for row in self.layout:
            for key in row:
                button = Button(
                    text=key.upper() if self.is_caps else key,
                    size_hint=(1, 1),
                    font_size=24,
                    font_name="assets/fonts/Poppins/Poppins-Medium.ttf"
                )
                button.bind(on_press=self.key_press)
                keyboard_layout.add_widget(button)
        self.add_widget(keyboard_layout)

        # 功能键部分
        function_layout = BoxLayout(orientation="horizontal", size_hint=(1, None), height=75, spacing=2)

        # 大小写切换键
        caps_lock = Button(text="Caps", size_hint=(0.2, 1), font_size=24,font_name="assets/fonts/Poppins/Poppins-Medium.ttf")
        caps_lock.bind(on_press=self.toggle_caps)
        function_layout.add_widget(caps_lock)

        # 空格键
        space = Button(text="Space", size_hint=(0.4, 1), font_size=24,font_name="assets/fonts/Poppins/Poppins-Medium.ttf")
        space.bind(on_press=self.space_press)
        function_layout.add_widget(space)

        # 退格键
        backspace = Button(text="Delete", size_hint=(0.2, 1), font_size=24,font_name="assets/fonts/Poppins/Poppins-Medium.ttf")
        backspace.bind(on_press=self.backspace_press)
        function_layout.add_widget(backspace)
        
        # 清空键
        clear = Button(text="Clear", size_hint=(0.2, 1), font_size=24,font_name="assets/fonts/Poppins/Poppins-Medium.ttf")
        clear.bind(on_press=self.clear_text)
        function_layout.add_widget(clear)

        self.add_widget(function_layout)

    def key_press(self, instance):
        """处理按键事件"""
        self.target_input.text += instance.text

    def backspace_press(self, instance):
        """处理退格事件"""
        self.target_input.text = self.target_input.text[:-1]

    def space_press(self, instance):
        """处理空格事件"""
        self.target_input.text += " "
        
    def clear_text(self, instance):
        """清空输入框"""
        self.target_input.text = ""

    def toggle_caps(self, instance):
        """切换大小写"""
        self.is_caps = not self.is_caps
        self.clear_widgets()
        self.create_keyboard()

        
class InputNameScreen(BaseScreen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        layout = BoxLayout(
            orientation="vertical",
            spacing=50,
        )

        title_bar = YellowBar(
            title_text="DEPOSIT",
        )
        layout.add_widget(title_bar)
        
        main_layout = BoxLayout(
            orientation="vertical",
            spacing=50,
            padding=[100, 20, 100, 20],
        )
        
        first_row = BoxLayout(
            orientation="vertical",
            spacing=20,
            size_hint=(1, 0.9),
        )

        # 添加输入框提示文字
        prompt_label = Label(
            text="Please enter your item name:",
            font_size=36,
            color=(0, 0, 0, 1),
            halign="left",
            valign="center",
            size_hint=(1, 0.1),
            font_name="assets/fonts/Poppins/Poppins-Medium.ttf"
        )
        prompt_label.bind(size=prompt_label.setter("text_size"))
        first_row.add_widget(prompt_label)

        self.input_box = TextInput(
            hint_text="Input Item Name...",
            font_size=28,
            multiline=True,
            size_hint=(1, 0.1),
            background_color=(0.9, 0.9, 0.9, 1),
            font_name="assets/fonts/Poppins/Poppins-Light.ttf"
        )
        first_row.add_widget(self.input_box)


        # 添加自定义键盘
        keyboard = CustomKeyboard(self.input_box, size_hint=(1, 0.6))
        first_row.add_widget(keyboard)

        # 添加按钮布局
        second_row = BoxLayout(
            orientation="horizontal",
            spacing=0,
            size_hint=(1, 0.1),
        )

        # Back 按钮
        back_button = RoundedButton(
            text="BACK",
            font_size=24,
            size_hint=(None, 1),
            width=200,
            custom_color=(0, 0, 0, 1),
            font_name="assets/fonts/Poppins/Poppins-Bold.ttf"
        )
        second_row.add_widget(back_button)
        back_button.bind(on_press=self.go_back)
        
        spacer = BoxLayout(size_hint=(1, 1))
        second_row.add_widget(spacer)

        # Next 按钮     
        next_button = RoundedButton(
            text="NEXT",
            font_size=24,
            size_hint=(None, 1),
            width=200,
            custom_color=(0, 0, 0, 1),
            font_name="assets/fonts/Poppins/Poppins-Bold.ttf"
        )
        second_row.add_widget(next_button)
        next_button.bind(on_press=self.go_to_photo_screen)
        
        main_layout.add_widget(first_row)
        main_layout.add_widget(second_row)

        layout.add_widget(main_layout)

        end_bar = YellowBar(
            title_text="",
        )
        layout.add_widget(end_bar)

        self.add_widget(layout)

    def key_down_handler(self, keyboard, keycode, text, modifiers):
        """处理键盘按下事件"""
        if text:
            self.input_box.text += text
        elif keycode[1] == "backspace":
            self.input_box.text = self.input_box.text[:-1]

    def reset(self):
        """重置输入框内容"""
        self.input_box.text = ""

    def go_back(self, instance):
        """返回操作"""
        self.reset()  
        self.manager.current = "choose_interact_type"

    def go_to_photo_screen(self, instance):
        """检查文件夹是否存在并跳转到下一界面"""
        name = self.input_box.text.strip()
        if not name:
            print("Name cannot be empty!")
            self.show_error_popup(f"Item name cannot be empty!")
            return

        # 检查是否有重复文件夹
        folder_path = f"data/{name}"
        if os.path.exists(folder_path):
            print(f"A folder with the name '{name}' already exists. Please choose a different name.")
            self.show_error_popup(f"An item with the name '{name}' already exists.\nPlease choose a different name.")
            return

        self.reset() 
        
        self.manager.get_screen("photo_audio_screen").item_name = name
        self.manager.switch_to("photo_audio_screen", mode="deposit")

    
    def show_error_popup(self, message):
        """显示错误提示"""
        from kivy.uix.popup import Popup
        from kivy.uix.label import Label
        from kivy.uix.button import Button
        from kivy.uix.boxlayout import BoxLayout

        # 创建一个布局
        layout = BoxLayout(orientation="vertical", padding=24, spacing=10)
        layout.add_widget(Label(text=message, font_size=24))
        close_button = Button(text="OK", size_hint=(1, 0.3), font_size=24)
        layout.add_widget(close_button)

        # 创建弹窗
        popup = Popup(
            title="Invalid Input",
            content=layout,
            size_hint=(0.6, 0.5),
            auto_dismiss=False,
        )

        # 绑定关闭按钮
        close_button.bind(on_press=popup.dismiss)
        popup.open()