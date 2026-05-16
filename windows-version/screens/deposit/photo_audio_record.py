
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from screens.components import BaseScreen, RoundedButton, YellowBar
from database.db_operations import insert_deposit, update_taken
from kivy.core.image import Image as CoreImage

import cv2
import sounddevice as sd
import wave
import os
from kivy.uix.image import Image
from kivy.clock import Clock
from kivy.graphics.texture import Texture


class PhotoAudioScreen(BaseScreen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.item_name = None
        self.photo_path = None
        self.audio_path = None
        
        self.camera = None
        self.preview_mode = False
        self.default_photo_path = "assets\default_photo.png"
        
        self.recording_active = False
        self.record_timer = 0
        self.max_duration = 60
        self.default_audio_path = "assets\default_audio.wav"
        
        self.mode = None
        print(f"[DEBUG] Initialized PhotoAudioScreen with mode: {self.mode}")

        layout = BoxLayout(
            orientation="vertical",
            spacing=50,
        )
        
        self.title_bar = YellowBar(
            "",
        )
        layout.add_widget(self.title_bar)
        
        main_layout = BoxLayout(
            orientation="horizontal",
            spacing=100,
            padding=[80, 20, 80, 20],
        )
        
        first_col = BoxLayout(
            orientation="vertical",
            spacing=50,
            size_hint=(0.5, 1),
        )

        camera_aspect_ratio = 4 / 3

        self.image_widget = Image(
            size_hint=(1, None),
            height=300,
            allow_stretch=True,
            keep_ratio=True,
        )
        first_col.add_widget(self.image_widget)
        
        self.display_default_photo()

        # 动态调整图片高度以匹配比例
        def update_image_height(*args):
            container_width = first_col.width
            self.image_widget.height = container_width / camera_aspect_ratio

        # 绑定窗口大小变化时调整高度
        first_col.bind(width=update_image_height)
        
        button_layout = BoxLayout(
            orientation="horizontal",
            size_hint=(1, 0.2),
            spacing=20
        )

        # 摄像头按钮
        self.camera_frame = RoundedButton(
            text="Open Camera",
            font_size=24,
            size_hint=(1, 1),
            custom_color=(0, 0, 0, 1),
            font_name="assets/fonts/Poppins/Poppins-Bold.ttf"
        )
        button_layout.add_widget(self.camera_frame)
        self.camera_frame.bind(on_press=self.toggle_camera_preview)

        self.record_button = RoundedButton(
            text="Record Audio",
            font_size=24,
            size_hint=(1, 1),
            custom_color=(0, 0, 0, 1),
            font_name="assets/fonts/Poppins/Poppins-Bold.ttf"
        )
        button_layout.add_widget(self.record_button)
        self.record_button.bind(on_press=self.toggle_recording)

        first_col.add_widget(button_layout)
    
        
        # 状态标签
        self.status_layout = BoxLayout(
            orientation="horizontal",
            size_hint=(0.7, 0.1),
            spacing=5
        )

        # 图标（默认状态图标）
        self.status_icon = Image(
            source="assets/Microphone.png",
            size_hint=(0.3, 1)
        )
        self.status_layout.add_widget(self.status_icon)

        # 标签
        self.status_label = Label(
            text="Ready to record audio",
            font_size=24,
            color=(0, 0, 0, 1),
            size_hint=(0.7, 1),
            font_name="assets/fonts/Poppins/Poppins-Medium.ttf"
        )
        self.status_layout.add_widget(self.status_label)

        first_col.add_widget(self.status_layout)

        second_col = BoxLayout(
            orientation="vertical",
            spacing=50,
            size_hint=(0.4, 1),
        )
        
        # 提示文本
        text_label = Label(
            text="Do you want to take a photo\nor leave a audio message?",
            font_size=36,
            halign="left",
            valign="middle",
            color=(0, 0, 0, 1),
            size_hint=(1, 0.6),
            font_name="assets/fonts/Poppins/Poppins-Medium.ttf"
            
        )
        second_col.add_widget(text_label)

        # 底部按钮
        self.button_layout = BoxLayout(orientation="horizontal", spacing=20, size_hint=(1, 0.1))

        spacer = BoxLayout(size_hint=(1, 1))
        self.button_layout.add_widget(spacer)
        
        next_button = RoundedButton(
            text="NEXT",
            font_size=24,
            size_hint=(None, 0.6),
            width=200,
            custom_color=(0, 0, 0, 1),
            font_name="assets/fonts/Poppins/Poppins-Bold.ttf"
        )
        self.button_layout.add_widget(next_button)
        next_button.bind(on_press=self.go_next)
        
        second_col.add_widget(self.button_layout)

        main_layout.add_widget(first_col)
        main_layout.add_widget(second_col)

        layout.add_widget(main_layout)

        end_bar = YellowBar(
            title_text="",
        )
        layout.add_widget(end_bar)

        self.add_widget(layout)
        
    def display_default_photo(self):
        """展示默认图片"""
        try:
            # 加载默认图片到纹理中
            default_texture = CoreImage(self.default_photo_path).texture
            self.image_widget.texture = default_texture
            print(f"[DEBUG] Default photo displayed: {self.default_photo_path}")
        except Exception as e:
            print(f"[ERROR] Failed to load default photo: {e}")


    def toggle_camera_preview(self, instance):
        """打开或关闭摄像头实时预览"""
        if not self.preview_mode:
            self.camera = cv2.VideoCapture(0)
            if not self.camera.isOpened():
                print("Error: Cannot access the camera")
                return
            self.preview_mode = True
            self.camera_frame.text = "Capture Photo"
            Clock.schedule_interval(self.update_camera_preview, 1.0 / 30.0)
        else:
            ret, frame = self.camera.read()
            if ret:
                temp_folder = "temp"
                if not os.path.exists(temp_folder):
                    os.makedirs(temp_folder)

                for file in os.listdir(temp_folder):
                    if file.endswith(".jpg"):
                        os.remove(os.path.join(temp_folder, file))

                self.photo_path = os.path.join(temp_folder, "temp_photo.jpg")
                cv2.imwrite(self.photo_path, frame)
                print(f"Photo temporarily saved: {self.photo_path}")

                # 停止摄像头
                self.camera.release()
                self.camera = None
                self.preview_mode = False
                self.camera_frame.text = "Open Camera"
                Clock.unschedule(self.update_camera_preview)

                # 显示静态照片
                self.display_photo(frame)
            else:
                print("Error: Could not capture photo")

    def update_camera_preview(self, dt):
        """更新摄像头实时画面"""
        if self.camera:
            ret, frame = self.camera.read()
            if ret:
                frame = cv2.rotate(frame, cv2.ROTATE_180)
                
                frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                buf = frame.tobytes()
                texture = Texture.create(size=(frame.shape[1], frame.shape[0]), colorfmt='rgb')
                texture.blit_buffer(buf, colorfmt='rgb', bufferfmt='ubyte')
                self.image_widget.texture = texture

    def display_photo(self, frame):
        """显示拍摄的静态照片"""
        frame = cv2.rotate(frame, cv2.ROTATE_180)

        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        buf = frame.tobytes()
        texture = Texture.create(size=(frame.shape[1], frame.shape[0]), colorfmt='rgb')
        texture.blit_buffer(buf, colorfmt='rgb', bufferfmt='ubyte')
        self.image_widget.texture = texture
    
    def toggle_recording(self, instance):
        """开始或停止录音"""
        if not self.recording_active:
            self.start_recording()
        else:
            self.stop_recording()

    def start_recording(self):
        """开始录音"""
        try:
            # 检查设备默认采样率
            device_info = sd.query_devices(sd.default.device, 'input')
            self.fs = int(device_info['default_samplerate'])

            # 删除旧的临时音频
            temp_folder = "temp"
            if not os.path.exists(temp_folder):
                os.makedirs(temp_folder)

            for file in os.listdir(temp_folder):
                if file.endswith(".wav"):
                    os.remove(os.path.join(temp_folder, file))

            # 设置临时音频路径
            self.audio_path = os.path.join(temp_folder, "temp_audio.wav")

            # 开始录音
            self.recording = sd.rec(int(self.max_duration * self.fs), samplerate=self.fs, channels=1, dtype='int16')
            self.recording_active = True
            self.record_timer = 0
            Clock.schedule_interval(self.update_recording_status, 1.0)
            self.status_label.text = "Recording... 0s"
            self.record_button.text = "Stop Recording"
            print("Recording started.")
        except Exception as e:
            print(f"Error starting recording: {e}")

    def stop_recording(self):
        """停止录音"""
        if not self.recording_active:
            return

        try:
            sd.stop()
            Clock.unschedule(self.update_recording_status)
            self.recording_active = False

            with wave.open(self.audio_path, 'w') as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(self.fs)
                wf.writeframes(self.recording[:int(self.record_timer * self.fs)].tobytes())

            self.status_label.text = "Recording saved!"
            self.record_button.text = "Record Audio"
            print(f"Audio saved at {self.audio_path}")
        except Exception as e:
            print(f"Error stopping recording: {e}")

    def update_recording_status(self, dt):
        """更新录音状态"""
        self.record_timer += dt
        if self.record_timer >= self.max_duration:
            self.status_label.text = "Maximum duration reached. Stopping recording..."
            self.stop_recording()
        else:
            self.status_label.text = f"Recording... {int(self.record_timer)}s"
            
    
    def on_enter(self):
        """根据全局模式动态更新界面"""
        mode = self.manager.get_mode()
        self.mode = mode
        if mode == "deposit":
            self.title_bar.update_title("DEPOSIT")
            self.status_label.text = "Ready to record audio for deposit."
        elif mode == "take":
            self.title_bar.update_title("TAKE")
            self.status_label.text = "Ready to record audio for retrieval."
        else:
            self.title_bar.update_title("UNKNOWN MODE")
            self.status_label.text = "Unknown mode. Please check."
            
    def reset(self):
        """重置界面内容"""
        self.photo_path = None
        self.audio_path = None
        self.image_widget.texture = None
        self.camera_frame.text = "Open Camera"
        self.status_label.text = "Ready to record audio"
        self.record_button.text = "Record audio"
        self.recording_active = False
        self.record_timer = 0
        self.preview_mode = False
        self.display_default_photo()

        # 停止摄像头预览（如果未停止）
        if self.camera:
            self.camera.release()
            self.camera = None
            Clock.unschedule(self.update_camera_preview)

        # 清理临时目录中的文件
        temp_folder = "temp"
        if os.path.exists(temp_folder):
            for file in os.listdir(temp_folder):
                if file.endswith(".jpg") or file.endswith(".wav"):
                    os.remove(os.path.join(temp_folder, file))
            print("Temporary files cleared.")

    
    def prepare_folder(self):
        """创建项目文件夹"""
        if not self.item_name:
            print("Item name is required to create folder!")
            return

        self.folder_path = f"data\{self.item_name}"
        if not os.path.exists(self.folder_path):
            os.makedirs(self.folder_path)
            print(f"Folder created: {self.folder_path}")

    def go_back(self, instance):
        """返回上一个界面并清理临时数据"""
        temp_folder = "temp"
        if os.path.exists(temp_folder):
            for file in os.listdir(temp_folder):
                if file.endswith(".jpg") or file.endswith(".wav"):
                    os.remove(os.path.join(temp_folder, file))
            print("Temporary photos cleared.")

        self.reset()
        self.manager.current = "input_name_screen"
            
    def save_file(self, file_path, default_path, folder_path, file_name):
        """保存文件到指定文件夹，如果文件不存在则使用默认文件"""
        if file_path and os.path.exists(file_path):
            final_path = os.path.join(folder_path, file_name)
            os.rename(file_path, final_path)
            print(f"File moved to: {final_path}")
        else:
            final_path = os.path.join(folder_path, file_name)
            if not os.path.exists(final_path):
                if os.path.exists(default_path):
                    import shutil
                    shutil.copy(default_path, final_path)
            print(f"No file provided, using default file: {final_path}")
        return final_path

    def go_next(self, instance):
        """跳过到下一个界面"""

        if self.manager.get_mode() == "deposit":
            self.prepare_folder()
            self.photo_path = self.save_file(
                file_path=self.photo_path,
                default_path=self.default_photo_path,
                folder_path=self.folder_path,
                file_name=f"{self.item_name}_deposit_photo.jpg"
            )

            self.audio_path = self.save_file(
                file_path=self.audio_path,
                default_path=self.default_audio_path,
                folder_path=self.folder_path,
                file_name=f"{self.item_name}_deposit_audio.wav"
            )
            
            insert_deposit(
                name=self.item_name,
                deposit_photo_path=self.photo_path,
                deposit_audio_path=self.audio_path
            )
            
            print(f"Stored photo: {self.photo_path}, audio: {self.audio_path}")
            
            self.reset()
            self.manager.switch_to("open_door_screen", mode="deposit")

        else:
            current_item = self.manager.current_item
            if current_item:
                self.item_name = current_item["name"]
                print(f"item name {self.item_name}")

                self.prepare_folder()
                
                self.photo_path = self.save_file(
                    file_path=self.photo_path,
                    default_path=self.default_photo_path,
                    folder_path=self.folder_path,
                    file_name=f"{self.item_name}_taken_photo.jpg"
                )

                self.audio_path = self.save_file(
                    file_path=self.audio_path,
                    default_path=self.default_audio_path,
                    folder_path=self.folder_path,
                    file_name=f"{self.item_name}_taken_audio.wav"
                )

                # 更新数据库
                update_taken(
                    item_name=self.item_name,
                    taken_photo_path=self.photo_path,
                    taken_audio_path=self.audio_path
                )
                print(f"Updated taken photo: {self.photo_path}, audio: {self.audio_path}")
            else:
                print("No item selected for take operation!")

            self.manager.current_item = None
            self.reset()
            self.manager.switch_to("choose_interact_type", mode=None)

        
