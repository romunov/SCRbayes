SCRi.fn <-
function(scrobj,
         ni=1100,burn=100,skip=2,nz=200,theta=NA,
         Msigma=1,Mb=0,Msex=0,Msexsigma = 0,Xeff=NULL,Xsex=NULL, ss.prob=NULL,
coord.scale=5000,area.per.pixel=1,thinstatespace=1,maxNN=20,dumprate=1000){

# Added input vector ss.prob, which gives a proportional (RSF-like) weight to each node in the statespace

call <- match.call()

traps<-scrobj$traps
captures<-scrobj$captures
statespace<-scrobj$statespace
alive<-scrobj$alive
Xd<- scrobj$Xd

## current SCRh and prior versions:  trapid, individual, occasion
##
## EDF: session, individual, occasion, trapID
## Now we assume EDF as input and need to reorganize to the old format so the rest of the code works

captures<- cbind(captures[,4],captures[,2],captures[,3])



if(   length(unique(captures[,2])) != length(min(captures[,2]):max(captures[,2])) ) {
 cat("Error: individuals not numbered sequentially, renumbering them now",fill=TRUE)
 captures[,2]<- as.numeric(factor(captures[,2]))
}


# ni = number of iterations, total
# burn = number to discard
# skip = thin rate (i.e., keep one in skip iterations)
# Msigma = 0 fits non-spatial model
# statespace (formerly GRID) is the discrete grid of the study area
# nz = number of "all zero" encounter histories to add
##traps=datafile containing the XY locations of the grid center points
###captures=data file containing the ID of the animal, the Sampling occassion the animals was captured on, and the number of the trap the animal was captured in.
###statespace=data file containing a fine grid of points

## SCRf.fn expands code to include 3 types of "fixed" covariates that are easy to deal with
##  (1) trap-specific only
##  (2) time-specific only
##  (3) trap and time-specific (e.g., effort)
## all of these can be put into a trap x time matrix "Xeff"
## Other types: vary by individual (sex)
## Spatial: habitat or things that vary over the state-space
##
##  "effort" = Xeff = ntraps x ndays matrix or NULL.
##  Xeff1 = test data, X traps x Y periods (random numbers) assume log(eff)


 Y<-captures
 traplocs<-traps[,2:3]
 MASK<-as.matrix(traps[,4:ncol(traps)])
 nind<-max(Y[,2])
 T<-dim(MASK)[2]
 M<-nind+nz   # total size of data set
 ntraps<-nrow(traplocs)

##################
##################
##################
##################
totalarea<- nrow(statespace)*area.per.pixel

thinned<- seq(1,nrow(statespace),thinstatespace)
statespace<-statespace[thinned,]
Xd<-Xd[thinned]
goodbad<-statespace[,3]
G<-statespace[,1:2]
G<-G[goodbad==1,]
Gunscaled<-G
Xd<- Xd[goodbad==1]
nG<-nrow(G)

new.area.per.pixel<- totalarea/nG

# The following lines thin the statespace probability weights to match the thinned statespace
#########################################################
	if(!is.null(ss.prob)){
		ss.prob = ss.prob[thinned]
		ss.prob = ss.prob[goodbad==1]
	}
##########################################################


###
###
## following lines scale coordinate system. This is kind of arbitrary.
###
###

mgx<-min(traplocs[,1])
mgy<-min(traplocs[,2])
traplocs[,1]<-(traplocs[,1]-min(traplocs[,1]))/coord.scale
traplocs[,2]<-(traplocs[,2]-min(traplocs[,2]))/coord.scale
G[,1]<-(G[,1]-mgx)/coord.scale
G[,2]<-(G[,2]-mgy)/coord.scale



###
# create "Data" vector but with trap mask information
###
msk2<-array(NA,c(nind+nz,T,ntraps))
for(i in 1:(nind+nz)){
msk2[i,1:T,1:ntraps]<-t(MASK[1:ntraps,1:T])
}
msk2<-as.vector(msk2)
###
###
# expand the data to a 3-d array
Ynew<-array(0,dim=c(nind,T,ntraps))
Ynew[cbind(Y[,2],Y[,3],Y[,1])]<-1
Y<-Ynew
###
### data augmentation
###
Yaug<-array(0,dim=c(nind+nz,T,ntraps))
for(j in 1:nind){
Yaug[j,1:T,1:ntraps]<-Y[j,1:T,1:ntraps]
}

if(!is.null(Xeff)){
Xeffnew<-array(0,dim=c(nind+nz,T,ntraps))
for(j in 1:M){
Xeffnew[j,1:T,1:ntraps]<-t(Xeff)
}
Xeff.tf<-TRUE
}
if(is.null(Xeff)){
Xeffnew<-array(0,dim=c(nind+nz,T,ntraps))
Xeff.tf<-FALSE
}
Xeff<-Xeffnew
if(!is.null(Xsex)){
Xsexnew<-c(Xsex,rep(NA,nz))
}
if(is.null(Xsex)){
Xsexnew<-rep(0,nind+nz)
}
Xsex<-Xsexnew
sex.naflag<-is.na(Xsex)



###
# create covariate of previous capture
###
prevcap<-array(0,c(nind+nz,T,ntraps))
for(i in 1:(nind)){
for(j in 1:ntraps){
tmp<-Yaug[i,1:T,j]
if(any(tmp==1)){
 fst<- min( (1:T)[tmp==1] )
 if(fst<T)
  prevcap[i,(fst+1):T,j]<-1
}
}
}
prevcap<-as.vector(prevcap)
###


### String out "alive" into a full-dimensional array
#### Robin Russell July 2013
alive.trues<-array(1, c(nind + nz, T, ntraps))
for(i in 1:nind)
{
for(t in 1:T)
{
alive.trues[i,T,1:ntraps]<-alive[i,t]
}
}
alive.trues<-as.vector(alive.trues)
aliveid<-alive.trues[msk2==1]


##
## vectorize all the data objects
##
arr.trues <- array(TRUE, c(nind+nz,T,ntraps))
idx<-which(arr.trues, arr.ind = TRUE)
y<-as.vector(Yaug)
y<-y[msk2==1 & alive.trues==1]
Xeff<-as.vector(Xeff)
Xeff<-Xeff[msk2==1 & alive.trues==1]
prevcap<-prevcap[msk2==1 & alive.trues==1]

## Robin Russell July 2013
indid.LM<- idx[msk2 == 1, 1]
### Robin fixed this 8/13/2013
indid <- idx[msk2 == 1 & alive.trues==1, 1]
###indid<-idx[msk2==1,1]
repid<-idx[msk2==1 & alive.trues==1,2]
trapid<-idx[msk2==1 & alive.trues==1,3]


getNN<-function(maxNN,G){
###
### Data processing -- this block of code determines a neighborhood
### for every pixel. That information is used in the MCMC updating
### of activity centers. Some tuning would be required
# G = statespace grid
nG<-nrow(G)

NN<-matrix(NA,nrow=nG,ncol=maxNN)
#By having a constant maxNN then the neighborhoods are
## symmetric

for(i in 1:nG){
od<- sqrt( (G[i,1]-G[,1])^2  +  (G[i,2]-G[,2])^2  )
NN[i,1:maxNN]<-order(od)[1:maxNN]
}
numnn<-rep(0,nrow(NN))
for(i in 1:nG){
# set to NA any element that is not also a neighbor. i.e.,
# remove neighbors for which i is not in their neighborhood.
for(j in 1:ncol(NN)){
if(any(NN[NN[i,j],]==i,na.rm=TRUE)) next
else
 NN[i,j]<-NA
 }
numnn[i]<-sum(!is.na(NN[i,]))
NN[i,1:numnn[i]]<-NN[i,!is.na(NN[i,])]
}

if(min(numnn)<3)
 cat("State-space grid has isolated or nearly-isolated cells increase maxNN or modify state-space",fill=TRUE)

out<-list(NN=NN,numnn=numnn)
return(out)
}
hld<-getNN(maxNN,G)
NN<-hld$NN
numnn<-hld$numnn

###
###
## this block of code selects starting coordinates for each individual
###
###

centers1<-rep(NA,nind)
for(i in 1:nind){
tt<-t(as.matrix(Yaug[i,,]))
tt<-row(tt)[tt==1]   # which traps was animal captured in
xxx<-as.matrix(traplocs[tt,],ncol=2,byrow=FALSE)  ## coordinates of those traps
av.coord<-colSums(xxx)/nrow(xxx)

dvec<-as.vector(e2dist(matrix(av.coord,ncol=2),G))  # finds closest grid pt
centers1[i]<-(1:length(dvec))[dvec==min(dvec)][1]   # that is initial loc
}
# assigns uncaptured animals a center point; modified by JFG 10/9/13 with ss.prob
centers2<-sample(1:nG,M-nind,replace=TRUE, prob=ss.prob)
centers<-c(centers1,centers2)
S<-G[centers,]   # initial locations for all M individuals

if(Msexsigma==0)
bsigma<- 1
if(Msexsigma==1)
bsigma <-c(3,3)

update.theta<-FALSE
if(is.na(theta)){
     theta<- .75
     update.theta<-TRUE
 }

loglam0<-log(.018)
beta.behave<-0
beta.sex<-0
# start beta1=0 so if there's no covariate this parameter is zeroed out
beta1<-0
lam0<-exp(loglam0)
psi<-.5  # not a good starting values
psi.sex <- mean(Xsex,na.rm=TRUE)
z<-c(rep(1,nind),rbinom(nz,1,psi))
if(sum(sex.naflag)>0)
Xsex[sex.naflag]<-rbinom(sum(sex.naflag),1,psi.sex) # modified 10/15/13 JFG - changed mean binom prob to mean of known pop. instead of .65

if(is.null(Xd)){
      Xd<-rep(1,nG)
  }
  beta.den<-0



###
###
##   initializing things and making utility funcs
###
###

lik.fn<-function(lpc,y1){
llvector.new<- -1*exp(lpc)
part2<- exp(exp(lpc[y1])) - 1
part2[part2==0]<-.Machine$double.eps
llvector.new[y1]<- llvector.new[y1]  + log(part2)
llvector.new
}




trapgridbig<-traplocs[trapid,]   # streteches out the trap coord matrix
y1<-y==1
c1<- (S[indid,1]-trapgridbig[,1])^2
c2<- (S[indid,2]-trapgridbig[,2])^2

gof.new<-gof.data<-rep(NA,(ni-burn)/skip)

out<-matrix(NA,nrow=(ni-burn)/skip,ncol=14)
dimnames(out)<-list(NULL,c("bsigma","sigma","bsigma2","sigma2","lam0","beta.behave","beta1(effort)","beta.sex","psi","psi.sex","Nsuper","theta","beta.density","D"))
zout<-matrix(NA,nrow=(ni-burn)/skip,ncol=M)
Sout<-matrix(NA,nrow=(ni-burn)/skip,ncol=M)
LLout<-matrix(NA, nrow=(ni-burn)/skip,ncol=2)
m<-1

# edits 8/14/2013
#LM1<-LM2<-matrix(NA,nrow=M,ncol=length(indid)/M)
LM1<-LM2<-matrix(0,nrow=M,ncol=length(indid.LM)/M)
ones<-rep(1,ncol(LM1))

if(Msexsigma==0)
lp.sigma<-Msigma*bsigma*(c1+c2)^theta
if(Msexsigma==1)
lp.sigma<-bsigma[Xsex[indid]+1]*(c1+c2)^theta

acc.count<-0
delta<-.05


for(i in 1:ni){
cat("iter: ",i,fill=TRUE)
########################
########################
########################
########################
# PART 1 OF THE MCMC ALGORITHM UPDATES THE REGRESSION PARAMETERS. FOR THIS MODEL
# THE REGRESSION PARAMETERS ARE (1) INTERCEPT (2) EFFECT OF PREVIOUS CAPTURE
# (BEHAVIORAL RESPONSE) (3) THE SPATIAL PARAMETER "sigma"
### Updating parameters here should only involve guys with z = 1 (i.e., members of the population)

### update loglam0
lp<-   loglam0 + Mb*beta.behave*prevcap - lp.sigma + beta1*Xeff + Msex*beta.sex*Xsex[indid]
loglam0c<-rnorm(1,loglam0,.1)
lpc<-  loglam0c + Mb*beta.behave*prevcap - lp.sigma + beta1*Xeff  + Msex*beta.sex*Xsex[indid]
llvector<-lik.fn(lp,y1)
llvector.new<-lik.fn(lpc,y1)
#LM1[1:length(LM1)]<-llvector.new
#LM2[1:length(LM2)]<- llvector
### July 2013
LM1[aliveid==1]<-llvector.new
LM2[aliveid==1]<- llvector
if(runif(1)< exp(sum(( (LM1[z==1,]-LM2[z==1,])%*%ones)))){
 loglam0<-loglam0c
 lam0<-exp(loglam0)
 llvector<-llvector.new
 lp<-lpc
 LM2<-LM1
}


## update theta
if(update.theta){
lp<-   loglam0 + Mb*beta.behave*prevcap - lp.sigma + beta1*Xeff + Msex*beta.sex*Xsex[indid]
thetac<-rnorm(1,theta,.02)
# theta must be  between exponential (.5) and gaussian (1)
if(thetac>=0.5 & thetac<=1){
if(Msexsigma==0)
lp.sigmac<-Msigma*bsigma*(c1+c2)^thetac
if(Msexsigma==1)
lp.sigmac<-bsigma[Xsex[indid]+1]*(c1 + c2)^thetac

lpc<-  loglam0 + Mb*beta.behave*prevcap - lp.sigmac + beta1*Xeff  + Msex*beta.sex*Xsex[indid]
llvector<-lik.fn(lp,y1)
llvector.new<-lik.fn(lpc,y1)
#LM1[1:length(LM1)]<-llvector.new
#LM2[1:length(LM2)]<- llvector
# Robin Russell
# July 2013
LM1[aliveid==1]<-llvector.new
LM2[aliveid==1]<- llvector

if(runif(1)< exp(sum(( (LM1[z==1,]-LM2[z==1,])%*%ones)))){
 theta<-thetac
 lp.sigma<-lp.sigmac
 llvector<-llvector.new
 lp<-lpc
 LM2<-LM1
}
}

}








### Update bsigma
## do this differently depending on if sigma depends on sex
if(Msexsigma==0){
bsigmac<-exp(rnorm(1,log(bsigma),delta))
lp.sigmac<- Msigma*bsigmac*(c1+c2)^theta
lpc<-  loglam0 + Mb*beta.behave*prevcap - lp.sigmac + beta1*Xeff  + Msex*beta.sex*Xsex[indid]
llvector.new<- lik.fn(lpc,y1)
##LM1[1:length(LM1)]<- llvector.new
LM1[aliveid==1]<- llvector.new
## July 2013
if(runif(1)< exp(sum(( (LM1[z==1,]-LM2[z==1,])%*%ones)))){
 lp.sigma<-lp.sigmac
 bsigma<-bsigmac
 llvector<-llvector.new
 lp<-lpc
 LM2<-LM1
 acc.count<-  acc.count - 1
}
else{
 acc.count<-acc.count+1
}
}

if(Msexsigma==1){
bsigmac<-c(exp(rnorm(1,log(bsigma[1]),2*delta)),bsigma[2])
lp.sigmac<- bsigmac[Xsex[indid]+1]*(c1+c2)^theta
lpc<-  loglam0 + Mb*beta.behave*prevcap - lp.sigmac + beta1*Xeff  + Msex*beta.sex*Xsex[indid]
llvector.new<- lik.fn(lpc,y1)
###LM1[1:length(LM1)]<- llvector.new
# July 2013
LM1[aliveid==1]<- llvector.new
if(runif(1)< exp(sum(( (LM1[z==1,]-LM2[z==1,])%*%ones)))){
 lp.sigma<-lp.sigmac
 bsigma<-bsigmac
 llvector<-llvector.new
 lp<-lpc
 LM2<-LM1
# delta<-delta*1.2
}
else{
#   delta<- delta*.8
}

bsigmac<-c(bsigma[1],exp(rnorm(1,log(bsigma[2]),2*delta)))
lp.sigmac<- bsigmac[Xsex[indid]+1]*(c1+c2)^theta
lpc<-  loglam0 + Mb*beta.behave*prevcap - lp.sigmac + beta1*Xeff  + Msex*beta.sex*Xsex[indid]
llvector.new<- lik.fn(lpc,y1)
####LM1[1:length(LM1)]<- llvector.new
# July 2013
LM1[aliveid==1]<- llvector.new
if(runif(1)< exp(sum(( (LM1[z==1,]-LM2[z==1,])%*%ones)))){
 lp.sigma<-lp.sigmac
 bsigma[2]<-bsigmac[2]
 llvector<-llvector.new
 lp<-lpc
 LM2<-LM1
}

}
cat("DELTA: ",delta,fill=TRUE)

if(any(bsigma<0) ){
cat("negative bsigma....",fill=TRUE)
 return(0)
}

if(Msex==1){
beta.sexc<- rnorm(1,beta.sex,.1)
lpc<-  loglam0 + Mb*beta.behave*prevcap - lp.sigma + beta1*Xeff  + Msex*beta.sexc*Xsex[indid]
llvector.new<- lik.fn(lpc,y1)
##LM1[1:length(LM1)]<- llvector.new
# July 2013
LM1[aliveid==1]<- llvector.new
if(runif(1)< exp(sum(( (LM1[z==1,]-LM2[z==1,])%*%ones)))){
 beta.sex<- beta.sexc
 llvector<-llvector.new
 lp<-lpc
 LM2<-LM1   # LM2 is current value
}
}

### This code allows a "local behavioral effect" as opposed to a conventional
###  "global effect" which would not be trap specific.
if(Mb==1){
beta.behave.c<- rnorm(1,beta.behave,.1)
lpc<-  loglam0 + Mb*beta.behave.c*prevcap - lp.sigma + beta1*Xeff  + Msex*beta.sex*Xsex[indid]
llvector.new<- lik.fn(lpc,y1)
##LM1[1:length(LM1)]<- llvector.new
## July 2013
LM1[aliveid==1]<- llvector.new
if(runif(1)< exp(sum(( (LM1[z==1,]-LM2[z==1,])%*%ones)))){
 beta.behave<- beta.behave.c
 llvector<-llvector.new
 lp<-lpc
 LM2<-LM1   # LM2 is current value
}
}



if(Xeff.tf){
### This block of code below deals with effort.
beta1c<- rnorm(1,beta1,.1)
lpc<-  loglam0 + Mb*beta.behave*prevcap - lp.sigma + beta1c*Xeff   + Msex*beta.sex*Xsex[indid]
llvector.new<- lik.fn(lpc,y1)
##LM1[1:length(LM1)]<- llvector.new
## July 2013
LM1[aliveid==1]<- llvector.new
if(runif(1)< exp(sum(( (LM1[z==1,]-LM2[z==1,])%*%ones)))){
 beta1<- beta1c
 llvector<-llvector.new
 lp<-lpc
 LM2<-LM1   # LM2 is current value
}
}

##############################
##############################
########################
########################
########################
# PART 2 OF THE MCMC ALGORITHM UPDATES THE DATA AUGMENTATION PARAMETERS
# THIS INCLUDES THE LATENT "z" VARIABLES AS WELL AS THE CRITICAL
# PARAMETER "psi"
########################
########################

# This is the data augmentation part. This code updates each z[i]
# for all i=1,2,...M individuals. z[i]=1 is a "real" animal that lives
# in S, whereas z[i]=0 are excess zeros in the data set
# this is an application of Bayes rule to get Pr(z=1| y[i,,]=0)

probz<- exp( rowsum(llvector[indid>nind],indid[indid>nind]) ) # only for nind+1...M
probz<- (probz*psi )/(probz*psi + (1-psi))
z[(nind+1):M]<-rbinom(M-nind,1,probz)
psi<-rbeta(1,1+sum(z),1+M-sum(z))

###
###  This updates SEX identifier  and sex ratio
###

if(!is.null(Xsex)){
# here we only switch sex state if sex is missing for an individual
tmp.sex<-Xsex
tmp.sex[sex.naflag]<- 1-Xsex[sex.naflag]

if(Msexsigma==0)
lp.sigmac<-Msigma*bsigma*(c1+c2)^theta
if(Msexsigma==1)
lp.sigmac<-bsigma[tmp.sex[indid]+1]*(c1+c2)^theta

lpc<-  loglam0 + Mb*beta.behave*prevcap - lp.sigmac + beta1*Xeff  + Msex*beta.sex*tmp.sex[indid]     ## + sex contribution if sex is in the model!
llvector.new<-lik.fn(lpc,y1)
lik.othersex<- exp(rowsum(llvector.new,indid))

lik.sex<- exp( rowsum(llvector,indid) ) # need to do this only for MISSING SEX is done here for all animals
prior.curr<-(psi.sex^Xsex)*((1-psi.sex)^(1-Xsex))
prior.cand<-(psi.sex^tmp.sex)*((1-psi.sex)^(1-tmp.sex))

swtch<- sex.naflag & (runif(M,0,1)< ( (lik.othersex*prior.cand)/(lik.sex*prior.curr)))
Xsex[swtch]<- 1-Xsex[swtch]
psi.sex<-rbeta(1,.1+sum(Xsex[z==1]),.1+sum(z)-sum(Xsex[z==1]))

if(Msexsigma==0)
lp.sigma<-Msigma*bsigma*(c1+c2)^theta
if(Msexsigma==1)
lp.sigma<-bsigma[Xsex[indid]+1]*(c1+c2)^theta

lp<-  loglam0 + Mb*beta.behave*prevcap - lp.sigma + beta1*Xeff  + Msex*beta.sex*Xsex[indid]
llvector.new<- lik.fn(lp,y1)
####LM1[1:length(LM1)]<- llvector.new
## July 2013
LM1[aliveid==1]<- llvector.new
llvector<-llvector.new
LM2<-LM1
}

########################
########################
## PART III OF THE ALGORITHM -- THIS BLOCK OF CODE UPDATES THE
## ACTIVITY CENTERS.
########################
########################


##################################################################
### Gets new centers with probability weightings - 10/9/13 JFG
	if (!is.null(ss.prob)){
		newcenters = rep(NA, M)
		for (gc in 1:M){
			newcenters[gc] <- sample(1:numnn[centers[gc]],size=1,replace=TRUE, prob=ss.prob[na.omit(unique(NN[centers[gc],]))])
      	}
	}
	 if (is.null(ss.prob)){
		 newcenters <- trunc(runif(M, 0, numnn[centers])) + 1
       }
###################################################################	
newcenters<- NN[cbind(centers,newcenters)]
   # these probabilities are needed in the Metrpolis "acceptance probability" calculation
   # since the proposal is not symmetric (i.e., near the boundary of the state-space)
qnew<- 1/numnn[centers]
qold<- 1/numnn[newcenters]
Sc<-G[newcenters,]
c1c<- (Sc[indid,1]-trapgridbig[,1])^2
c2c<- (Sc[indid,2]-trapgridbig[,2])^2

if(Msexsigma==0)
lp.sigmac<-Msigma*bsigma*(c1c+c2c)^theta
if(Msexsigma==1)
lp.sigmac<-bsigma[Xsex[indid]+1]*(c1c+c2c)^theta
lpc<- loglam0+ Mb*beta.behave*prevcap - lp.sigmac + beta1*Xeff + Msex*beta.sex*Xsex[indid]

llvector.new<- lik.fn(lpc,y1)
####LM1[1:length(LM1)]<- llvector.new
LM1[aliveid==1]<- llvector.new
likdiff<- (LM1-LM2)%*%ones


likdiff[z==0]<-0   # all other things equal, this lines sets acceptance prob to 1 for z=0 guys


### edits 7/23/2013
logprior.new<-    Xd[newcenters]*beta.den
logprior.old<-    Xd[centers]*beta.den

#likdiff<-likdiff + log(qold/qnew)
### I think dimension of these is wrong......
likdiff<-likdiff + log(qold/qnew)  + (logprior.new-logprior.old)

accept<- runif(M)<exp(likdiff)
cat("accept rate: ",mean(accept),fill=TRUE)
S[accept,]<-Sc[accept,]
centers[accept]<-newcenters[accept]
c1<- (S[indid,1]-trapgridbig[,1])^2
c2<- (S[indid,2]-trapgridbig[,2])^2
LM2[accept,]<-LM1[accept,]


### This block of code updates a density covariate parameter
beta.den.c<- rnorm(1,beta.den,.25)
numerator.new <- exp(Xd*beta.den.c)
loglik.new <- Xd[centers]*beta.den.c - log(sum(numerator.new))
numerator.old <- exp(Xd*beta.den)
loglik.old <-  Xd[centers]*beta.den - log(sum(numerator.old))
if(  runif(1)< exp( sum(loglik.new) - sum(loglik.old) ) ){
 beta.den<-beta.den.c
}


####
####
### update some objects
####
####
####

if(Msexsigma==0)
lp.sigma<-Msigma*bsigma*(c1+c2)^theta
if(Msexsigma==1)
lp.sigma<-bsigma[Xsex[indid]+1]*(c1+c2)^theta

lp<-  loglam0 + Mb*beta.behave*prevcap - lp.sigma + beta1*Xeff  + Msex*beta.sex*Xsex[indid]
llvector<- lik.fn(lp,y1)
LM2<-LM1


########################
########################
########################
##
## save output if iteration is past burn-in and using a thin-rate of "skip"
##
########################
########################
########################

if( (i>burn) & (i%%skip == 0) ){

sigma<- sqrt(1/(2*bsigma))
if(Msexsigma == 0){
sigmatmp<-c(sigma,sigma)
bsigmatmp<-c(bsigma,bsigma)
}
else{
sigmatmp<-sigma
bsigmatmp<-bsigma
}

#####
## Jan 25 GoF stuff right here for JWM paper
## 09/19/2011
#####
# mean of "real individuals" (not fixed zeros)
# realguys<- z[indid]==1
# cat(sum(realguys)," real observations for GoF",fill=TRUE)

logmu<- loglam0 + Mb*beta.behave*prevcap - lp.sigma + beta1*Xeff  + Msex*beta.sex*Xsex[indid]
mu<- ( 1-exp(-exp(logmu)))*z[indid]  # zeros out the z=0 guys so they contribute nothing

# JFG Added Oct. '13 these lines calculate the probability of observing the data given the parameter values
#logmu.array <- array(log(exp(-exp(logmu)))*z[indid], dim=c(max(indid),max(repid), max(trapid)))
#logmu.array[as.matrix(captures[,c(2,3,1)])] <- array(log(1-exp(-exp(logmu)))*z[indid], dim=c(max(indid),max(repid), max(trapid)))[as.matrix(captures[,c(2,3,1)])]
#logmu.array[is.infinite(logmu.array)]=.Machine$double.min.exp
mu.array <- array(1-mu, dim=c(max(indid),max(repid), max(trapid)))
mu.array[as.matrix(captures[,c(2,3,1)])] <- 1 - mu.array[as.matrix(captures[,c(2,3,1)])]
logmu.array = log(mu.array)
n.nolik = sum(is.infinite(logmu.array))
logmu.array[is.infinite(logmu.array)]=.Machine$double.min.exp


newy<-rbinom(length(mu),1,mu)
gof.stats<-cbind(y,newy,mu)
gof.stats<-aggregate(gof.stats,list(indid),sum)
gof.data[m]<- sum( (sqrt(gof.stats[,2])-sqrt(gof.stats[,4]))[z==1]^2)
gof.new[m]<- sum(  (sqrt(gof.stats[,3])-sqrt(gof.stats[,4]))[z==1]^2)

#####
#####
#####
#####

density<- sum(z)/totalarea

zout[m,]<-z
Sout[m,]<- centers
# Compute the likelihood of the data given the model/parameter values
LLout[m,]<- c(sum(logmu.array), n.nolik)#prod(c(mu.array))
out[m,]<-c(bsigmatmp[1],sigmatmp[1],bsigmatmp[2],sigmatmp[2],
lam0, beta.behave, beta1,beta.sex,psi,psi.sex,sum(z),theta,beta.den,density)
print(out[m,])
if(m%%dumprate==0){
#write a file here not implemented yet
}
m<-m+1
}


}

#### vector of model effects
parms.2.report<-
    c(TRUE,TRUE,Msexsigma==1,Msexsigma==1,
TRUE, Mb==1,
Xeff.tf,
 Msex==1, TRUE, (Msex==1|Msexsigma==1), TRUE, update.theta,
sum(Xd)>0,
TRUE ) # JFG 10/15/13 edited so that psi.sex is included if Msexsigma = 1.


#model
#         ni=1100,burn=100,skip=2,nz=200,theta=NA,
#         Msigma=1,Mb=0,Msex=0,Msexsigma = 0,Xeff=NULL,Xsex=NULL,

out<- list(mcmchist=out,G=G,Gunscaled=Gunscaled,traplocs=traplocs,Sout=Sout,zout=zout, likelihood=LLout,statespace=statespace,gof.data=gof.data,gof.new=gof.new,call=call,parms2report=parms.2.report) # JFG edited to return the likelihood

class(out) <- c("scrfit","list")

return(out)

}
