function  f = iFGG_3d_type2mod(F,knots,accuracy,GridListx,GridListy,GridListz)
%Description:
%This code implements the "accelerated" Gaussian-gridding-based inverse 
%type-II (uniform --> nonuniform) NUFFT described in Greengard and Lee [1]. 
%The gridding approach is very similar to previous work by Nguyen and Liu 
%[2]; the only difference is the use of a different convolution kernel ([1] 
%claims that the Gaussian kernel has computational advantages). Both 
%algorithms allow the user to specify the numerical precision of the 
%routine, but [1] provides a nice summary that would allow one to tabulate 
%the appropriate variable values for each desired numerical precision. Code 
%for [2] is also available upon request.
%
%This code performs T-2 NUFFTs from rectangular cubes of size N=[Nx,Ny,Nz] 
%(not counting frequency padding for image interpolation). The approximate 
%DFT attains errors on the order of 1e-6 (for more or less accuracy, vary 
%the optional "accuracy" parameter). 
%
%Inputs:
%       f: frequency-domain data (a complex Mx1 vector) unwrapped from a
%           matrix knots: k-space locations at which the data were measured
%           (an Mx3 vector). This data must be in double format.
%       knots: the frequency locations of the data points. These locations
%           should be normalized to correspond to the grid boundaries
%           [-N/2, N/2 -1/N], N even. If the knots are not scaled
%           properly, they will be shifted and scaled into this normalized
%           form.
%       N = [Nx,Ny,Nz]: the 1x3 vector denoting the size of the spatial
%           grid in the image domain. This parameter will determine the
%           spatial extent of the image.
%Optional Inputs:
%       accuracy: a positive integer indicating the desired number of 
%           digits of accuracy   
%Outputs:
%       F: the 3D NUFFT (approximate DFT) of f, with dimension [Nx,Ny,Nz].
%
%
%Usage Notes:
%In order for this function to work, the C
%file "FGG_Convolution3D.c" must be compiled into a Matlab executable 
%(cmex) with the following command in the command prompt:
%
%mex FGG_Convolution3D.c
%
%A note on the effect of M_sp on the algorithm's accuracy:
%[R,M_sp]=[2,3]  ==> 1e-3 accuracy
%[R,M_sp]=[2,6]  ==> single precision
%[R,M_sp]=[2,9]  ==> 1e-9 accuracy
%[R,M_sp]=[2,12] ==> double precision
%
%References:
%[1] L. Greengard and J. Lee, "Accelerating the Nonuniform Fast Fourier
%Transform," SIAM Review, Vol. 46, No. 3, pp. 443-454.
%[2] N. Nguyen and Q. H. Liu, "Nonuniform fast fourier transforms," SIAM J.
%Sci. Comput., 1999.
%
%
%Please note:
%This code is free to use, but we ask that you please reference the source,
%as this will encourage future funding for more free AFRL products. This
%code was developed through the AFOSR Lab Task "Moving-Target Radar Feature
%Extraction."
%Project Manager: Arje Nachman
%Principal Investigator: Matthew Ferrara
%Date: November 2008
%
%Code by (send correspondence to):
%Matthew Ferrara, Research Mathematician
%AFRL Sensors Directorate Innovative Algorithms Branch (AFRL/RYAT)
%Matthew.Ferrara@wpafb.af.mil

%Explanation of variables used
%bw             The bandwidth of the input data (fmax-fmin)
%D              A [Nx,Ny,Nz] deconvolution matrix formed from the 3D 
%               kronecker product of E4_x, E4_y, and E4_z  
%E1, E2, E3     factors of the Gaussian filter in the frequency domain
%               (the Gaussian is factored to eliminate redundant
%               exponential calculations)
%E4             The Gaussian deconvolution filter
%f              The Mx1 vector of nonuniformly-spaced frequency data given
%               as input to the NUFFT routine
%f_tau          The [R*Nx,R*Ny] matrix of uniformly-spaced fequency-domain
%               data values after "gridding"
%F_tau          The FFT of f_tau
%F              The approximate DFT of f (the deconvolved FFT of f_tau)
%fmean          The average frequencies of the input data  
%j              Index variable that indexes the convolution loop through
%               the data points (1 <= j <= M)
%kmin           The minimum knot values of the input data (1x3 vector)
%kmax           The maximum knot values of the input data (1x3 vector)
%knots          The Mx1 vector of frequency locations given as input to
%               the NUFFT. 
%M              The number of (k-space) data points (the length of the
%               input data vector f)
%M_sp           Width of the frequency-domain box used in the approximate
%               interpolation of each data point onto the frequency grid
%               (M_sp=6 for single precision and M_sp=12 for double
%               precision)
%N              The image size of the NUFFT output (N=[Nx, Ny, Nz])
%Nx             The length of the image in the x dimension
%Ny             The length of the image in the y dimension
%Nz             The length of the image in the z dimension
%padF           A zero-padded version of F
%R              Oversampling ratio for gridding in the frequency (data)
%               domain
%S              The [Nx,Ny]-sized kronecker product of E4_x and E4_y  
%scale          1x3 vector used to scale the input data locations into the
%               normalized form
%shift          1x3 vector used to shift the input data locations into the
%               normalized form
%tau            The 3x1 Gaussian kernel spreading factor
%End Explanation of variables


[Nx,Ny,Nz]=size(F);
N=[Nx,Ny,Nz];
M=size(knots,1);
%Ensure that the knots fit in a 2*pi interval


dgx=GridListx(2)-GridListx(1);
dgy=GridListy(2)-GridListy(1);
dgz=GridListz(2)-GridListz(1);

kminx=-(Nx/2)*dgx;
kmaxx=kminx+(Nx-1)*dgx;
kminy=-(Ny/2)*dgy;
kmaxy=kminy+(Ny-1)*dgy;
kminz=-(Nz/2)*dgz;
kmaxz=kminz+(Nz-1)*dgz;


kmin=[kminx,  kminy, kminz];
kmax=[kmaxx,  kmaxy, kmaxz];
%The BW that covers the whole k-space region when confined to the
%specified grid spacing
bw=[kmaxx-kminx,  kmaxy-kminy,kmaxz-kminz ];


scale = -N/2./([min(GridListx) min(GridListy) min(GridListz) ] );

knots=repmat(scale,[M,1]).*knots;
knots=mod(2*pi*knots./repmat(N,[M,1]),2*pi);%shift to [0,2*pi)




%Type-II NUFFT:
if nargin<3, accuracy=6; end
R=2;
%M_sp is the length of the convolution kernel
M_sp=accuracy;%This gives roughly 6 digits of accuracy
%The variance, tau, of the Gaussian filter may be different in each
%dimension
%tau = M_sp./(N.^2);%I was initially using this value
tau = (pi*M_sp./(N.*N*R*(R-.5)));%Suggested value of tau by Greengard [1]
%The length of the oversampled grid
M_r = round(R*N);

%Precompute E_3, the constant component of the (truncated) Gaussian:
E_3x(1,1:M_sp) = exp(-((pi*(1:M_sp)/M_r(1)).^2)/tau(1));
%don't waste (slow) exponential calculations
E_3x=[fliplr(E_3x(1:(M_sp-1))),1,E_3x];
E_3y(1,1:M_sp) = exp(-((pi*(1:M_sp)/M_r(2)).^2)/tau(2));
%don't waste (slow) exponential calculations
E_3y=[fliplr(E_3y(1:(M_sp-1))),1,E_3y];
E_3z(1,1:M_sp) = exp(-((pi*(1:M_sp)/M_r(3)).^2)/tau(3));
%don't waste (slow) exponential calculations
E_3z=[fliplr(E_3z(1:(M_sp-1))),1,E_3z];

%Precompute E_4 (for devonvolution after the FFT)
kx_vec = (-Nx/2):(Nx/2-1);
%The Hadamard Inverse of the Fourier Transform of the truncated Gaussian
E_4x(1:Nx,1)=sqrt(pi/tau(1))*exp(tau(1)*(kx_vec.^2));
ky_vec = (-Ny/2):(Ny/2-1);
%The Hadamard Inverse of the Fourier Transform of the truncated Gaussian
E_4y(1,1:Ny)=sqrt(pi/tau(2))*exp(tau(2)*(ky_vec.^2));%
kz_vec = (-Nz/2):(Nz/2-1);
%The Hadamard Inverse of the Fourier Transform of the truncated Gaussian
E_4z(1:Nz,1)=sqrt(pi/tau(3))*exp(tau(3)*(kz_vec.^2));%
%End initialization of constant variables
%Deconvolve
S=kron(E_4z,E_4x*E_4y);%Scalars for 3D kronecker product (matrix must be 
                       %reshaped)
D=permute(reshape(S,[Nx,Nz,Ny]),[1,3,2]);
F=F.*D/M;
%Zero pad for convolution on finer mesh in frequency domain
padF=zeros(round(R*Nx),round(R*Ny),round(R*Nz));
padF((round(.5*(R-1)*Nx) + 1) : round(.5*(R+1)*Nx), (round(.5*(R-1)*Ny) + 1) : round(.5*(R+1)*Ny),...
    (round(.5*(R-1)*Nz) + 1) : round(.5*(R+1)*Nz))=F;
f_tau = fftshift(ifftn(ifftshift(padF)));
f=zeros(M,1); f_r=f; f_i=f;
[f_r,f_i]=...
    FGG_Convolution3D_type2(double(real(f_tau(:))),double(imag(f_tau(:))),...
    double(knots),E_3x,E_3y,E_3z,[M_sp, tau(1), tau(2), tau(3), M_r(1), M_r(2), M_r(3)]);
f = f_r+sqrt(-1)*f_i;
