sim.data <-
function (N = 200, sigma = 0.3, loglam0 = log(0.35),
          K = 12,
    statespace ,
    traplocs,
    Xss = NULL, alpha1 = 0,
    coord.scale = 5000,  Ntel=2, nfixes=500)
{
    statespace[, 1:2] <- statespace[, 1:2]/coord.scale
    traplocs <- traplocs/coord.scale
    ntraps <- nrow(traplocs)
    if (is.null(Xss))
        Xss <- rep(1, nrow(GRID))
    G <- statespace[, 1:2]
    goodbad <- statespace[, 3]
    G <- G[goodbad == 1, ]
    nG <- nrow(G)
    sprobs <- exp(alpha1 * Xss[goodbad == 1])
    sprobs <- sprobs/sum(sprobs)
    centers <- sample(1:nG, N, replace = TRUE, prob = sprobs)
    S <- G[centers, ]
    par(mar=c(3,3,3,6))
    spatial.plot(statespace,Xss,cx=2,add=FALSE)
    points(S,pch=20)
    Y <- array(NA, c(N, K, ntraps))
    #Ytel<- matrix(NA,nrow=nG,ncol=Ntel)
    Ytel<-NULL
    sex<-rbinom(N,1,.5)  # sex ratio = .5

    if(length(sigma)==2){
      sigma.v<- sigma[sex+1]

  }
  else{
      sigma.v<-rep(sigma,N)
      }
    for (i in 1:N) {
        lp <- loglam0 - (1/(2*sigma.v[i]^2)) * ((S[i, 1] - traplocs[, 1])^2 +
            (S[i, 2] - traplocs[, 2])^2)
        lambda<- exp(lp)
        pcap <- 1 - exp(-1 * lambda)
        for (t in 1:K) {
            ttt <- rbinom(ntraps, 1, pcap)
            Y[i, t, 1:ntraps] <- ttt
        }
        if(Ntel>0 & i<= Ntel){
            ## Xss needs in encounter model too
            log.lambda<-
-(1/(2*sigma.v[i]^2)) * ((S[i, 1] - G[, 1])^2 + (S[i, 2] - G[, 2])^2) +alpha1*Xss
           # rsf.probs<- exp(log.lambda)/sum(exp(log.lambda))
           # Ytel[,i]<- rmultinom(1,nfixes,rsf.probs)
           Ytel<- rbind(Ytel,cbind( rnorm(nfixes,S[i,1],sigma.v[i]),
                                    rnorm(nfixes,S[i,2],sigma.v[i]),i))
       }
   }

   attr(Ytel,"sex")<- sex[1:Ntel]


    ndet <- apply(Y, c(1, 2), sum)
    ind.captured <- apply(ndet, 1, sum)
    cat("total captures: ", sum(Y), fill = TRUE)
    cat("total individuals: ", sum(ind.captured > 0), fill = TRUE)
    Y <- Y[ind.captured > 0, , ]
    sex<-sex[ind.captured>0]
    MASK <- matrix(1, ntraps, K)
    traplocs <- traplocs * coord.scale
    trapout <- cbind(1:nrow(traplocs), traplocs, MASK)
    dimnames(trapout) <- list(1:nrow(traplocs), c("LOC_ID", "X_Coord",
        "Y_Coord", as.character(1:ncol(MASK))))
##    write.csv(trapout, "traps.csv", row.names = FALSE)
    o <- NULL
    for (i in 1:dim(Y)[1]) {
        z <- Y[i, , ]
        o <- rbind(o, cbind(i, row(z)[z > 0], col(z)[z > 0]))
    }
    y <- cbind(o[, 3], o[, 1], o[, 2])
    y <- y[order(y[, 1]), ]
    dimnames(y) <- list(1:nrow(y), c("trapid", "individual",
        "sample"))
#    write.csv(y, "captures.csv", row.names = FALSE)
#    write.csv(statespace, "statespace.csv", row.names = FALSE)
    list(Y = Y, MASK = MASK, traplocs = traplocs, Xss = Xss,Ytel=Ytel,
         Xsex=sex,statespace=statespace)
}
