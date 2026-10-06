import cv2, numpy as np, os
from scipy import ndimage as ndi
D='userzip/AIRA-Static Images Anime Version/'
S=1024
def load(n): return cv2.resize(cv2.imread(D+f'anime_{n}.jpeg'),(S,S),interpolation=cv2.INTER_AREA)
base=load('eyes_open').astype(np.float32)
MA=np.load('ua/M_A.npy')
def get(n):
    im=load(n)
    if n=='mouth_A':
        im=cv2.warpAffine(im,MA,(S,S),flags=cv2.INTER_CUBIC,borderMode=cv2.BORDER_REPLICATE)
    return im.astype(np.float32)
def soft_ellipse(cx,cy,rx,ry,feather):
    yy,xx=np.mgrid[0:S,0:S].astype(np.float32)
    d=np.sqrt(((xx-cx)/rx)**2+((yy-cy)/ry)**2)
    return np.clip((1-d)/feather+0.0,0,1)[...,None] if False else np.clip((1.0-d)/(feather),0,1)[...,None]
MOUTH=soft_ellipse(505,410,115,95,0.45)
EYES=np.maximum(soft_ellipse(440,296,92,40,0.5)[...,0],soft_ellipse(590,302,92,40,0.5)[...,0])[...,None]
def comp(dst,src,m): return dst*(1-m)+src*m
closed=comp(base,get('eyes_closed'),EYES)
# --- cutout alpha from the base image (white background) ---
src=load('eyes_open'); f=src.astype(np.float32)
mn=f.min(axis=2); mx=f.max(axis=2)
white=(mn>=222)&((mx-mn)<=14)
lab,n=ndi.label(white)
border=set(np.unique(np.r_[lab[0],lab[-1],lab[:,0],lab[:,-1]]))-{0}
sizes=ndi.sum(white,lab,range(1,n+1)); cms=ndi.center_of_mass(white,lab,range(1,n+1))
big=[i+1 for i,(sz,(cy,cx)) in enumerate(zip(sizes,cms)) if sz>40 and not (300<cx<760 and 160<cy<540)]
bgm=np.isin(lab,list(border)+big)
near=ndi.binary_dilation(bgm,iterations=3)
a=np.ones(mn.shape,np.float32); a[bgm]=0
soft=near&~bgm; a[soft]=np.clip((244-mn[soft])/(244-190),0,1)
a=cv2.GaussianBlur(a,(0,0),0.5)
alpha=np.clip(a,0.001,1)[...,None]
def finish(img,path):
    col=np.clip((img-255*(1-alpha))/alpha,0,255); col[a>0.98]=img[a>0.98]
    out=np.dstack([col,a*255]).astype(np.uint8)
    out=cv2.resize(out,(768,768),interpolation=cv2.INTER_AREA)
    cv2.imwrite(path,out)
os.makedirs('ua/out/combined',exist_ok=True)
MAP={'neutral':'mouth_neutral','A':'mouth_A','E':'mouth_E','FV':'mouth_FV','L':'mouth_L','MPB':'mouth_MBP','O':'mouth_0','TH':'mouth_TH'}
for eyes,eb in (('open',base),('closed',closed)):
    for k,fn in MAP.items():
        finish(comp(eb,get(fn),MOUTH),f'ua/out/combined/AIRA_combo_{eyes}_{k}.png')
finish(base,'ua/out/AIRA_base_neutral.png')
def L(p):
    o=cv2.imread(p,-1);al=o[...,3:]/255.;return (o[...,:3]*al+255*(1-al)).astype('uint8')
rows=[]
for eyes in ('open','closed'):
    rows.append(np.hstack([L(f'ua/out/combined/AIRA_combo_{eyes}_{k}.png')[60:360,200:560] for k in MAP]))
cv2.imwrite('ua/sheet.png',cv2.resize(np.vstack(rows),None,fx=0.55,fy=0.55,interpolation=cv2.INTER_AREA))
dark=np.zeros((768,768,3),np.uint8);dark[:]=(40,160,60)
o=cv2.imread('ua/out/combined/AIRA_combo_open_neutral.png',-1);al=o[...,3:]/255.
cv2.imwrite('ua/prev.png',(o[...,:3]*al+dark*(1-al)).astype(np.uint8))
