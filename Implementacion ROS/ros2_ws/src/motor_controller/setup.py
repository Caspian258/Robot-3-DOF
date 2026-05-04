from setuptools import setup

package_name = 'motor_controller'

setup(
    name=package_name,
    version='0.0.1',
    packages=[package_name],
    install_requires=['setuptools','matplotlib'],
    zip_safe=True,
    entry_points={
        'console_scripts': [
            'pd_gui    = motor_controller.pd_gui_node:main',
        ],
    },
)