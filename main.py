import os,requests,datetime,time
from tkinter import * 
from threading import Thread
#D:\osu!\Songs

HEADERS = {
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36",
}
params = {
    "n":"1"
}


def save(locate):
    text = ""
    i = 0
    for filename in os.listdir(locate):
        try:
            fname = filename.split(maxsplit=1)
            id = int(fname[0])
            text += f"{str(id)} {fname[1]}\n"
            i += 1
            #print(id)
        except:
            pass

    #print(f'圖譜保存完成\n圖譜總計:{i}')
    with open('save.txt','w') as f:
        f.write(text)
    return i

def search(setid:str):
    url = f'https://api.chimu.moe/v1/set/{setid}'
    r = requests.get(url,headers=HEADERS).json()
    if r:
        setid = r.get('SetId')
        title = r.get('Title')
        return title
    else:
        return None

def download(setid:str):
    title = search(setid)
    if title:
        url = f"https://api.chimu.moe/v1/download/{setid}"
        r = requests.get(url,headers=HEADERS)
        if r.status_code == 200:
            with open(f'{setid} {title}.osz',mode='wb') as file:
                file.write(r.content)
            return f"id:{setid} 下載成功"
        else:
            return f"id:{setid} 下載失敗"
    else:
        return f"id:{setid} 未找到"


def btn1_command():
    t = en.get()
    if t:
        try:
            os.listdir(t)
            lb2.config(text=f"存放路徑: {t}")
            count = save(t)
            lb2.config(text=f"紀錄已完成!\n共有{count}組圖譜")
        except FileNotFoundError:
            lb2.config(text=f"找不到此路徑")
    else:
        lb2.config(text="圖譜存放位置為空")

def btn2_command():
        server = Thread(target=btn2_command2)
        server.start()

def btn2_command2():
    lb2.config(text=f"下載中...")
    with open('save.txt',mode='r') as file:
        list = []
        for line in file.readlines():
            id = line[:-1].split(maxsplit=1)[0]
            list.append(id)
    l = 0
    for i in list:
        l += 1
        t = download(i)
        t += f"\n已完成:{l}/{len(list)}"
        lb2.config(text=t)
        time.sleep(3)
        

win = Tk()
win.title('osu圖譜紀錄器')
win.geometry("300x200")
win.resizable(False,False)

btn1 = Button(text="生成紀錄",command=btn1_command,width=10,height=2)
btn1.place(x=40,y=130)


btn2 = Button(text="下載圖譜",command=btn2_command,width=10,height=2)
btn2.place(x=170,y=130)

lb1 = Label(text='歡迎使用osu圖譜紀錄器\n按下"生成紀錄"以生成紀錄或按下"下載圖譜"進行下載')
lb1.place(x=5,y=20)

lb2 = Label(text='')
lb2.place(x=95,y=55)

en = Entry()
en.place(x=75,y=90)

mainloop()