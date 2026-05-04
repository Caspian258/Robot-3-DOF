import sys
if sys.prefix == '/usr':
    sys.real_prefix = sys.prefix
    sys.prefix = sys.exec_prefix = '/home/bassdrumm/Documents/PlatformIO/Projects/motor_pd_controller/ros2_ws/install/motor_controller'
