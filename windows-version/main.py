from kivy.config import Config
Config.set("graphics", "fullscreen", "auto")  # 全屏模式
Config.set("graphics", "borderless", "1")  # 无边框窗口
Config.set("graphics", "width", "1440")
Config.set("graphics", "height", "900")
Config.set("graphics", "resizable", False)

from kivy.app import App
from kivy.uix.screenmanager import ScreenManager
from screens.home_page import HomePage, ChooseInteractType
from screens.deposit.input_item_name import InputNameScreen
from screens.deposit.photo_audio_record import PhotoAudioScreen
from screens.deposit.open_door import OpenDoorScreen
from screens.take.select_take_item import SelectTakeItemScreen
from screens.take.view_deposit_info import ViewDepositInfoScreen
from screens.memories.select_memories import HappyMemoriesScreen
from screens.memories.view_memories_details import ViewMemoriesDetailScreen
from screens.components import AudioPlayer
from database.db_setup import initialize_database
from kivy.clock import Clock

import serial
import threading
import time

import asyncio

class MyScreenManager(ScreenManager):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.current_item = {}
        self.audio_player = AudioPlayer()
        self.open_door_triggered  = False
        self.mode = None

        self.add_widget(HomePage(name="home"))
        self.add_widget(ChooseInteractType(name="choose_interact_type"))
        self.add_widget(InputNameScreen(name="input_name_screen"))
        self.add_widget(PhotoAudioScreen(name="photo_audio_screen"))
        self.add_widget(OpenDoorScreen(name="open_door_screen"))
        self.add_widget(SelectTakeItemScreen(name="select_take_screen"))
        self.add_widget(ViewDepositInfoScreen(name="view_deposit_info_screen"))
        self.add_widget(HappyMemoriesScreen(name="happy_memories_screen"))
        self.add_widget(ViewMemoriesDetailScreen(name="view_memories_details_screen"))

    def get_mode(self):
        return self.mode
        
    def set_mode(self, mode):
        self.mode = mode

    
    def switch_to(self, screen_name, mode=None):
        """切换到指定屏幕并设置模式"""
        if mode:
            self.set_mode(mode)
            print(f"[DEBUG] Switching to {screen_name} with mode: {self.mode}")
        self.current = screen_name

    def switch_to_choose_type(self):
        """切换到选择交互类型的屏幕"""
        self.switch_to("choose_interact_type", mode=None)
    
    def switch_back_to_home(self):
        """切换到选择交互类型的屏幕"""
        self.current = "home"
    
    def trigger_open_door(self):
        """设置开门触发器"""
        self.open_door_triggered = True
        print("Trigger set: open_door_triggered = True")

    def play_audio(self, audio_path):
        self.audio_player.play_audio(audio_path)

    

class CrazyKoalaApp(App):
    def build(self):
        self.screen_manager = MyScreenManager()
        return self.screen_manager

    def on_start(self):
        # 启动串口通信线程
        self.serial_thread9 = threading.Thread(target=self.serial_comm, daemon=True)
        # self.serial_thread.start()

    def serial_comm(self):
        """串口通信线程"""
        try:
            ser = serial.Serial("COM3", baudrate=115200, timeout=1)
            print("Serial connection established.")

            while True:
                # 检查是否有数据可读取
                if ser.in_waiting > 0:
                    data = ser.read(1)
                    if data:
                        number = int.from_bytes(data, byteorder="little")
                        print(f"Received: {number}")
                        Clock.schedule_once(lambda dt: self.handle_serial_input(number, ser))

                # 检查开门触发器
                if self.screen_manager.open_door_triggered:
                    print("Sending open door signal (byte4).")
                    ser.write(bytes([4]))
                    self.screen_manager.play_audio("assets\open_door.wav")
                    self.screen_manager.open_door_triggered = False

                time.sleep(1)
        except Exception as e:
            print(f"Error in serial communication: {e}")

    def handle_serial_input(self, number, ser):
        """处理接收到的串口输入"""
        if number == 0:
            print("Action: Play Goodbye audio.")
            self.screen_manager.play_audio("assets\goodbye.wav")
            # time.sleep(5)
            self.screen_manager.switch_back_to_home()
            # threading.Thread(target=self.play_audio_and_switch, args=(self.screen_manager,)).start()
            # asyncio.run(self.play_audio_and_switch(self.screen_manager))
        elif number == 1:
            print("Action: Play welcome audio.")
            self.screen_manager.play_audio("assets\start_interact.wav")
        elif number == 3:
            print("Action: Allow interaction.")
            self.screen_manager.switch_to_choose_type()
        elif number == 5:
            print("Action: Play meet people audio.")
            self.screen_manager.play_audio("assets\meet_people.wav")
        else:
            print(f"Unhandled input: {number}")
    
    # def play_audio_and_switch(self, screen_manager):
    #     self.screen_manager.play_audio("assets/goodbye.wav")
    #     time.sleep(5)  # 允许音频播放结束的时间
    #     self.screen_manager.switch_back_to_home()
    
    # async def play_audio_and_switch(self, screen_manager):
    #     await self.screen_manager.play_audio("assets/goodbye.wav")
    #     await asyncio.sleep(5)
    #     self.screen_manager.switch_back_to_home()

if __name__ == "__main__":
    initialize_database()
    CrazyKoalaApp().run()