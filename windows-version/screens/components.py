from kivy.graphics import Color, Rectangle
from kivy.uix.screenmanager import Screen
from kivy.uix.button import Button
from kivy.graphics import Color, RoundedRectangle
from kivy.uix.label import Label
from kivy.uix.boxlayout import BoxLayout
from playsound import playsound

import os
import threading

class BaseScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # 设置白色背景
        with self.canvas.before:
            Color(1, 1, 1, 1)
            self.bg = Rectangle(size=self.size, pos=self.pos)

        # 绑定窗口大小和位置的变化
        self.bind(size=self._update_bg, pos=self._update_bg)

    def _update_bg(self, *args):
        """动态调整背景矩形的大小和位置"""
        self.bg.size = self.size
        self.bg.pos = self.pos
      

class RoundedButton(Button):
    def __init__(self, custom_color=(0, 0, 0, 1), corner_radius=30, **kwargs):
        """
        Rounded Button with customizable corner radius.
        
        :param custom_color: Background color of the button (RGBA tuple)
        :param corner_radius: Radius for rounded corners (in pixels)
        """
        super().__init__(**kwargs)
        self.background_normal = ""
        self.background_color = (0, 0, 0, 0)
        self.custom_color = custom_color
        self.corner_radius = corner_radius
        self.bind(pos=self.update_canvas, size=self.update_canvas)

    def update_canvas(self, *args):
        """Dynamically update the button's canvas for rounded corners."""
        self.canvas.before.clear()
        with self.canvas.before:
            Color(*self.custom_color)
            RoundedRectangle(
                pos=self.pos,
                size=self.size,
                radius=[(self.corner_radius, self.corner_radius),
                        (self.corner_radius, self.corner_radius),
                        (self.corner_radius, self.corner_radius),
                        (self.corner_radius, self.corner_radius)]
            )

class YellowTitleBar(BoxLayout):
    def __init__(self, title_text="Title", button_text="BACK", on_button_press=None, **kwargs):
        super().__init__(**kwargs)
        self.orientation = "horizontal"
        self.size_hint = (1, 0.08)
        self.padding = [10, 5, 10, 5]
        self.spacing = 10

        # 设置背景颜色
        with self.canvas.before:
            Color(1, 0.9, 0, 1)
            self.rect = Rectangle(size=self.size, pos=self.pos)
        self.bind(size=self.update_rect, pos=self.update_rect)

        # 添加返回按钮
        self.back_button = RoundedButton(
            text=button_text,
            font_size=24,
            size_hint=(None, 0.9),
            width=150,
            custom_color=(0, 0, 0, 1),
            font_name="assets/fonts/Poppins/Poppins-Bold.ttf"
        )

        if on_button_press:
            self.back_button.bind(on_press=on_button_press)
        self.add_widget(self.back_button)

        # 添加标题文本
        self.title_label = Label(
            text=title_text,
            size_hint=(0.7, 1),
            color=(0, 0, 0, 1),
            font_size=36,
            halign="center",
            valign="middle",
            font_name="assets/fonts/Poppins/Poppins-Medium.ttf"
        )
        self.title_label.bind(size=self.title_label.setter("text_size"))
        self.add_widget(self.title_label)

        self.spacer = BoxLayout(size_hint=(0.1, 1))
        self.add_widget(self.spacer)

    def update_rect(self, *args):
        """更新背景矩形的尺寸和位置"""
        self.rect.size = self.size
        self.rect.pos = self.pos
    
    def update_title(self, title_text):
        """更新标题"""
        self.title_label.text = title_text

class YellowBar(BoxLayout):
    def __init__(self, title_text="Title", **kwargs):
        super().__init__(**kwargs)
        self.orientation = "horizontal"
        self.size_hint = (1, 0.08)
        self.padding = [10, 5, 10, 5]
        self.spacing = 10

        # 设置背景颜色
        with self.canvas.before:
            Color(1, 0.9, 0, 1)
            self.rect = Rectangle(size=self.size, pos=self.pos)
        self.bind(size=self.update_rect, pos=self.update_rect)


        # 添加标题文本
        self.title_label = Label(
            text=title_text,
            size_hint=(0.7, 1),
            color=(0, 0, 0, 1),
            font_size=36,
            halign="center",
            valign="middle",
            font_name="assets/fonts/Poppins/Poppins-Medium.ttf"
        )
        self.title_label.bind(size=self.title_label.setter("text_size"))
        self.add_widget(self.title_label)

    def update_rect(self, *args):
        """更新背景矩形的尺寸和位置"""
        self.rect.size = self.size
        self.rect.pos = self.pos
    
    def update_title(self, title_text):
        """更新标题"""
        self.title_label.text = title_text

class AudioPlayer():
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def play_audio(self, file_path=None):
        """播放音频"""
        if not file_path or not os.path.exists(file_path):
            print("Audio File Not Found!")
            return

        print(f"Playing Audio: {file_path}")
        
        threading.Thread(target=self._play_audio_thread, args=(file_path,), daemon=True).start()

    def _play_audio_thread(self, file_path):
        """在线程中播放音频"""
        try:
            playsound(file_path)
            print("Audio Playback Complete")
        except Exception as e:
            print(f"Error playing audio: {e}")


class InteractiveBoxLayout(BoxLayout):
    # 注册一个自定义事件
    def __init__(self, **kwargs):
        self.register_event_type('on_press')
        super().__init__(**kwargs)

    def on_touch_down(self, touch):
        if self.collide_point(*touch.pos):
            self.dispatch('on_press')
            return True
        return super().on_touch_down(touch)

    def on_press(self, *args):
        """这个方法将由事件监听器调用"""
        pass