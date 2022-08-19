import os,requests,datetime
locate = "D:\osu!\Songs"
HEADERS = {
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36",
    "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9",
    'upgrade-insecure-requests': '1',
    'dnt': '1'
}

cookie={
    "Cookie":{"XSRF-TOKEN":"",
    "osu_session":""},
    "DNT": "1"
}
data ={
    "username":"",
    "password":"",
    
}

def login():
    url2 = 'https://osu.ppy.sh/session'
    url = "https://osu.ppy.sh/beatmapsets/1792411"
    url3 = "https://osu.ppy.sh/home"
    url4 = "https://osu.ppy.sh/beatmapsets/1792411/download"
    url5 = "https://bm10.ppy.sh/d/1792411?fs=1792411 Persefone - The Majestic of Gaia.osz&fd=1792411.osz&ts=1659776717&cs=196002baaa81d6b5345e94c55fd75996&nv=0"
    s = requests.Session()
    s1 = s.post(url2,data=data,headers=HEADERS,verify=False)
    cookie = s1.cookies
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

login()