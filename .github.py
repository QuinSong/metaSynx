import os
import time


msg = 'add risk calculator complete'


os.system('git add .')
time.sleep(1)
os.system(f"git commit -m '{msg}'")
time.sleep(1)
os.system('git push')
time.sleep(3)
os.system('clear')
