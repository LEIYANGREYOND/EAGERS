function varargout = HelpScreen3b(varargin)
% HELPSCREEN3B MATLAB code for HelpScreen3b.fig
%      HELPSCREEN3B, by itself, creates a new HELPSCREEN3B or raises the existing
%      singleton*.
%
%      H = HELPSCREEN3B returns the handle to a new HELPSCREEN3B or the handle to
%      the existing singleton*.
%
%      HELPSCREEN3B('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in HELPSCREEN3B.M with the given input arguments.
%
%      HELPSCREEN3B('Property','Value',...) creates a new HELPSCREEN3B or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before HelpScreen3b_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to HelpScreen3b_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help HelpScreen3b

% Last Modified by GUIDE v2.5 27-Jan-2014 12:39:58

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @HelpScreen3b_OpeningFcn, ...
                   'gui_OutputFcn',  @HelpScreen3b_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before HelpScreen3b is made visible.
function HelpScreen3b_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to HelpScreen3b (see VARARGIN)

% Choose default command line output for HelpScreen3b
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);
global Model_dir
Pic_dir=fullfile(Model_dir, 'GUI','HelpTool','screenshots');
pFileName = fullfile(Pic_dir,'HelpScreen3b.jpg');
h=handles.axes1;
image(imread(pFileName),'Parent',h)
axis(h,'image')
axis(h,'off');
pFileName = fullfile(Pic_dir,'HelpScreen3b2.jpg');
h=handles.axes2;
image(imread(pFileName),'Parent',h)
axis(h,'image')
axis(h,'off');
pFileName = fullfile(Pic_dir,'HelpScreen3b3.jpg');
h=handles.axes3;
image(imread(pFileName),'Parent',h)
axis(h,'image')
axis(h,'off');
pFileName = fullfile(Pic_dir,'HelpScreen3b4.jpg');
h=handles.axes4;
image(imread(pFileName),'Parent',h)
axis(h,'image')
axis(h,'off');

% --- Outputs from this function are returned to the command line.
function varargout = HelpScreen3b_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


% --- Executes on button press in pushbuttonNext.
function pushbuttonNext_Callback(hObject, eventdata, handles)
% hObject    handle to pushbuttonNext (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
close(gcf)
HelpScreen4b()