import os,requests,datetime
locate = "D:\osu!\Songs"
HEADERS = {
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36",
}
params = {
    "n":"1"
}


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
            print(f"id:{setid} 下載成功")
        else:
            print(f"id:{setid} 下載失敗")
    else:
        print(f"id:{setid} 未找到")
   
download('2')