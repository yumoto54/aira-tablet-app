import cv2, numpy as np, glob, os, sys
D='userzip/AIRA-Static Images Anime Version/'
names=['eyes_open','eyes_closed','mouth_0','mouth_A','mouth_E','mouth_FV','mouth_L','mouth_MBP','mouth_TH','mouth_neutral']
S=1024
def load(n): return cv2.resize(cv2.imread(D+f'anime_{n}.jpeg'),(S,S),interpolation=cv2.INTER_AREA)
base=load('eyes_open'); bg=cv2.cvtColor(base,cv2.COLOR_BGR2GRAY).astype(np.float32)
# region to align on: upper face (eyes, brows, nose bridge) + head outline, excluding mouth/eyes-state area
mask=np.zeros((S,S),np.uint8); mask[int(S*0.05):int(S*0.36),int(S*0.2):int(S*0.8)]=255
res={}
for n in names:
    im=load(n); g=cv2.cvtColor(im,cv2.COLOR_BGR2GRAY).astype(np.float32)
    w=np.eye(2,3,dtype=np.float32)
    try:
        cc,w=cv2.findTransformECC(bg,g,w,cv2.MOTION_AFFINE,(cv2.TERM_CRITERIA_EPS|cv2.TERM_CRITERIA_COUNT,200,1e-6),mask,5)
    except Exception as e:
        print(n,'ECC fail',e); continue
    res[n]=w; print(n,'cc=%.3f'%cc,'scale=%.4f %.4f'%(w[0,0],w[1,1]),'shift=%.1f %.1f'%(w[0,2],w[1,2]))
np.save('ua/warps.npy',res,allow_pickle=True)
