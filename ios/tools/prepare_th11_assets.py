"""Prepare private TH11 1.00a resources from the user's original installation."""
from pathlib import Path
import argparse,hashlib,json,struct,shutil
import numpy as np
import soundfile as sf
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def decrypt(data,key,step,block,limit):
    out=bytearray(data);size=len(data);remaining=size-(size%block if size%block<block//4 else 0)-(size&1);cursor=0
    while remaining>0 and limit>0:
        n=min(block,remaining);linear=0
        for parity in (1,2):
            for pos in range(n-parity,-1,-2):
                out[cursor+pos]=data[cursor+linear]^key;key=(key+step)&255;linear+=1
        cursor+=n;remaining-=n;limit-=n
    return bytes(out)
def decode(data,size):
    dictionary=bytearray(8192);head=1;out=bytearray();at=0;mask=128;byte=0
    def bits(n):
        nonlocal at,mask,byte
        v=0
        for _ in range(n):
            if mask==128:byte=data[at] if at<len(data) else 0;at+=1
            v=(v<<1)|bool(byte&mask);mask>>=1
            if not mask:mask=128
        return v
    def put(v):
        nonlocal head
        out.append(v);dictionary[head]=v;head=(head+1)&8191
    while True:
        if bits(1):put(bits(8))
        else:
            offset=bits(13)
            if not offset:break
            for n in range(bits(4)+3):put(dictionary[(offset+n)&8191])
        if len(out)>size:raise ValueError('Invalid LZSS size')
    if len(out)!=size:raise ValueError('Incomplete LZSS output')
    return bytes(out)
def entry(path,name):
    data=path.read_bytes();header=decrypt(data[:16],27,55,16,16)
    if header[:4]!=b'THA1':raise ValueError('Not TH11 THA1')
    unpacked,packed,count=struct.unpack_from('<III',header,4);unpacked=(unpacked-123456789)&0xffffffff;packed=(packed-987654321)&0xffffffff;count=(count-135792468)&0xffffffff
    end=len(data)-packed;table=decode(decrypt(data[end:],62,155,128,packed),unpacked);cursor=0;entries=[]
    for _ in range(count):
        zero=table.index(0,cursor);n=table[cursor:zero].decode('ascii');cursor+=((zero-cursor+4)&~3)
        offset,size,_=struct.unpack_from('<III',table,cursor);cursor+=12;entries.append((n,offset,size))
    ciphers=[(27,55,64,10240),(81,233,64,12288),(193,81,128,12800),(3,25,1024,30720),(171,205,512,10240),(18,52,128,12800),(53,151,128,10240),(153,55,1024,8192)]
    for i,(n,offset,size) in enumerate(entries):
        if n!=name:continue
        next_at=entries[i+1][1] if i+1<len(entries) else end
        raw=decrypt(data[offset:next_at],*ciphers[sum(n.encode())&7])
        return raw if len(raw)==size else decode(raw,size)
    raise ValueError('Archive entry missing: '+name)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--original',type=Path,required=True);a=parser.parse_args();out=ROOT/'.local/assets';out.mkdir(parents=True,exist_ok=True)
    original=a.original/'th11.dat';exe=a.original/'th11.exe'
    if sha(exe)!='2978b17f6184d100d249d4311348dd30c5c32ec75c014b667a525b797d3d8813':raise ValueError('Original version differs')
    (out/'game').mkdir(exist_ok=True);shutil.copyfile(original,out/'game/th11.dat')
    (out/'fonts').mkdir(exist_ok=True)
    for n in ['font0.bin','font1.bin','font2.bin','font3.bin','cp932.bin','blend4444.bin']:
        shutil.copyfile(ROOT/'th11_web/assets/sdl-native/fonts'/n,out/'fonts'/n)
    formats=entry(original,'thbgm.fmt');(out/'music').mkdir(exist_ok=True);tracks=[]
    with (a.original/'thbgm.dat').open('rb') as source:
        if source.read(4)!=b'ZWAV':raise ValueError('Invalid thbgm header')
        for at in range(0,len(formats)-51,52):
            if not formats[at]:break
            name,offset,preload,intro,length=struct.unpack_from('<16sIIII',formats,at);name=name.split(b'\0')[0].decode('ascii')
            if struct.unpack_from('<HHIIHH',formats,at+32)!=(1,2,44100,176400,4,16):raise ValueError('Unsupported PCM')
            source.seek(offset);pcm=source.read(length)
            if len(pcm)!=length or intro%4 or not 0<=intro<length:raise ValueError('Invalid loop bounds')
            samples=np.frombuffer(pcm,dtype='<i2').reshape(-1,2);target=out/'music'/(Path(name).stem+'.ogg')
            if not target.exists() or sf.info(str(target)).frames!=len(samples):
                pending=target.with_suffix('.ogg.pending')
                with sf.SoundFile(str(pending),'w',samplerate=44100,channels=2,subtype='VORBIS',format='OGG',compression_level=.4) as f:
                    for start in range(0,len(samples),16384):f.write(samples[start:start+16384].astype(np.float32)/32768.)
                pending.replace(target)
            decoded,rate=sf.read(str(target),dtype='int16',always_2d=True)
            if rate!=44100 or decoded.shape!=samples.shape:raise ValueError('Music decoded frame count mismatch')
            tracks.append(dict(file=target.name,frames=len(samples),loopFrame=intro//4,pcmSha256=hashlib.sha256(pcm).hexdigest(),encodedSha256=sha(target),codec='vorbis',lossless=False))
            print(f'{len(tracks)}/18 {name}: verified frames and loop',flush=True)
    if len(tracks)!=18:raise ValueError('Missing music tracks')
    (out/'music-verification.json').write_text(json.dumps(tracks,indent=2)+'\n',encoding='utf-8')
    files={p.relative_to(out).as_posix():dict(bytes=p.stat().st_size,sha256=sha(p)) for p in out.rglob('*') if p.is_file() and p.name!='manifest.json'}
    (out/'manifest.json').write_text(json.dumps(dict(schema='th11-ios-assets/1',language='ja',files=files,originalExeSha256=sha(exe),originalDatSha256=sha(original),music='Vorbis; original PCM frame count and loop positions preserved; lossy audio',fonts='Original offline Windows GDI raster data'),indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
