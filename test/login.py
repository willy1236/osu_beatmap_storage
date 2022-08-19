import os,requests,datetime
locate = "D:\osu!\Songs"

#https://github.com/Shabinder/SpotiFlyer/issues/1178
#https://www.cnpython.com/qa/1391262

HEADERS = {
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36",
    "Accept-Encoding":"gzip, deflate, br",
    "Accept":"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
}

cookies={
    "XSRF-TOKEN":"",
    "osu_session":""
}

cookie2={
    "Cookie":{"XSRF-TOKEN":"",
    "osu_session":""},
    "DNT": "1"
}



data ={
    "username":"",
    "password":"",
    
}

id = "1452407"
url2 = 'https://osu.ppy.sh/session'
url4 = f"https://osu.ppy.sh/beatmapsets/{id}/download"
url5 = "https://bm10.ppy.sh/d/1792411?fs=1792411 Persefone - The Majestic of Gaia.osz&fd=1792411.osz&ts=1659776717&cs=196002baaa81d6b5345e94c55fd75996&nv=0"

def login():
    s = requests.Session()
    s1 = s.post(url2,data=data,headers=HEADERS,verify=False)
    print(s1)
    #cookie = s1.cookies

def get_map():
    r = requests.get(url4,headers=HEADERS,cookies=cookies)
    print(r)
    if r.status_code == 302:
        print(r.headers)
    #with open('test.html',mode='w',encoding='utf8') as file:
    #   file.write(r.text)


def get_map2():
    r= s.get(url4,headers=HEADERS,cookies=cookie,verify=False)
    print(r)
    #print(r.headers)
    if r.headers.get('location',None):
        url = r.headers.get('location')
        print('sec')
        r = requests.get(url,headers=HEADERS)
        print(r)
        with open('test.zip',mode='wb') as file:
            file.write(r.content)

get_map()