import os
import time


msg = 'reverted one commit back due to mt4 candles, conflict with claude files'


os.system('git add .')
time.sleep(1)
os.system(f"git commit -m '{msg}'")
time.sleep(1)
os.system('git push')
time.sleep(3)
os.system('clear')
