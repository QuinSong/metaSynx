import os
import time


msg = 'Chart cleanup fixed'


os.system('git add .')
time.sleep(1)
os.system(f"git commit -m '{msg}'")
time.sleep(1)
os.system('git push')
time.sleep(3)
os.system('clear')
