import os
#D:\osu!\Songs
locate = input('請輸入圖譜存放位置')
text = ""
i =0
for filename in os.listdir(locate):
    try:
        fname = filename.split(maxsplit=1)
        id = int(fname[0])
        text += f"{str(id)} {fname[1]}\n"
        i += 1
        #print(id)
    except:
        pass

print(f'圖譜保存完成\n圖譜總計:{i}')
with open('save.txt','w') as f:
    f.write(text)