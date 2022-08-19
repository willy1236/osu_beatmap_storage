import os,requests,datetime
locate = "D:\osu!\Songs"
HEADERS = {
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36",
    "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9"
}

cookie={
    "XSRF-TOKEN":"",
    "osu_session":""
}

def login():
    url = 'https://osu.ppy.sh/session'
    r = requests.post(url,headers=HEADERS)
    print(r.status,r.text)

def download():
    id = '1792411'
    url = f"https://osu.ppy.sh/beatmapsets/{id}/download"
    s = requests.Session()
    r = s.get(url,headers=HEADERS,cookies=cookie,verify=False)
    print(r.headers)
    with open('test.html',mode='wb') as file:
        file.write(r.content)
download()

# for filename in os.listdir(locate):
#     fname = filename.split()
#     id = int(fname[0])
#     url = f"https://osu.ppy.sh/beatmapsets/{fname[0]}/download"
#     print(id)
#     r = requests.get(url,headers=HEADERS,cookies=cookie)
#     #print(r.content)
#     print(r.status_code,r.headers)
#     print(r.headers.get('location',None))
#     #print(r.headers.get('set-cookie',None))
#     #f'https://bm4.ppy.sh/d/1001507?fs={filename}&fd=1001507.osz&ts={ts}&cs=60108f2f15464bc55ecdaf8b21a6def3&nv=0'
#     break
    
    #try:
        # id = int(fname[0])
        # url = f"https://osu.ppy.sh/beatmapsets/{id}/download"
        # print(id)
        # r = requests.get(url,headers=HEADERS,cookies=cookie)
        # #print(r.content)
        # print(r.status_code)
        # print(r.headers['location'])
        # #with open('test.zip',mode='wb') as file:
        #     #file.write(r.content)
    #    pass
    #except:
    #    pass