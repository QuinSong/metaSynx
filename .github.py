import os
import time


msg = '8th mt4 candle data attempt, after revert'


os.system('git add .')
time.sleep(1)
os.system(f"git commit -m '{msg}'")
time.sleep(1)
os.system('git push')
time.sleep(3)
os.system('clear')
