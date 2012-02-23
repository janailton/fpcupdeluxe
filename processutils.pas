{ Process utility unit
Copyright (C) 2012 Ludo Brands

This library is free software; you can redistribute it and/or modify it
under the terms of the GNU Library General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at your
option) any later version with the following modification:

As a special exception, the copyright holders of this library give you
permission to link this library with independent modules to produce an
executable, regardless of the license terms of these independent modules,and
to copy and distribute the resulting executable under terms of your choice,
provided that you also meet, for each linked independent module, the terms
and conditions of the license of that module. An independent module is a
module which is not derived from or based on this library. If you modify
this library, you may extend this exception to your version of the library,
but you are not obligated to do so. If you do not wish to do so, delete this
exception statement from your version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
for more details.

You should have received a copy of the GNU Library General Public License
along with this library; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
}
unit processutils;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, process, strutils;
type
  TProcessEx=class; //forward
  TDumpFunc = procedure (Sender:TProcessEx; output:string);
  TDumpMethod = procedure (Sender:TProcessEx; output:string) of object;
  TErrorFunc = procedure (Sender:TProcessEx;IsException:boolean);
  TErrorMethod = procedure (Sender:TProcessEx;IsException:boolean) of object;
  { TProcessEnvironment }

  TProcessEnvironment = class(TObject)
    private
      FEnvironmentList:TStringList;
      FCaseSensitive:boolean;
      function GetVarIndex(VarName:string):integer;
    public
      function GetVar(VarName:string):string;
      procedure SetVar(VarName,VarValue:string);
      property EnvironmentList:TStringList read FEnvironmentList;
      constructor Create;
      destructor Destroy; override;
    end;

  { TProcessEx }

  TProcessEx = class(TProcess)
    private
      FCmdLine: string;
      FExceptionInfoStrings: TstringList;
      FExecutable: string;
      FExitStatus: integer;
      FOnError: TErrorFunc;
      FOnErrorM: TErrorMethod;
      FOnOutput: TDumpFunc;
      FOnOutputM: TDumpMethod;
      FOutputStrings: TstringList;
      FOutStream: TMemoryStream;
      FProcess: TProcess;
      FProcessEnvironment:TProcessEnvironment;
      function GetExceptionInfo: string;
      function GetOutputString: string;
      function GetOutputStrings: TstringList;
      function GetParametersString: String;
      function GetProcessEnvironment: TProcessEnvironment;
      procedure SetOnError(AValue: TErrorFunc);
      procedure SetOnErrorM(AValue: TErrorMethod);
      procedure SetOnOutput(AValue: TDumpFunc);
      procedure SetOnOutputM(AValue: TDumpMethod);
      procedure SetParametersString(AValue: String);
    public
      procedure Execute;
      property Environment:TProcessEnvironment read GetProcessEnvironment;
      property ExceptionInfo:string read GetExceptionInfo;
      property ExceptionInfoStrings:TstringList read FExceptionInfoStrings;
      property ExitStatus:integer read FExitStatus;
      property OnError:TErrorFunc read FOnError write SetOnError;
      property OnErrorM:TErrorMethod read FOnErrorM write SetOnErrorM;
      property OnOutput:TDumpFunc read FOnOutput write SetOnOutput;
      property OnOutputM:TDumpMethod read FOnOutputM write SetOnOutputM;
      property OutputString:string read GetOutputString;
      property OutputStrings:TstringList read GetOutputStrings;
      property ParametersString:String read GetParametersString write SetParametersString;
      constructor Create(AOwner : TComponent); override;
      destructor Destroy; override;
    end;

// Convenience functions

function ExecuteCommandHidden(const Executable, Parameters: string; Verbose:boolean): integer; overload;
function ExecuteCommandHidden(const Executable, Parameters: string; var Output:string; Verbose:boolean): integer; overload;
procedure DumpConsole(Sender:TProcessEx; output:string);



implementation

{ TProcessEx }

function TProcessEx.GetOutputString: string;
begin
  result:=OutputStrings.Text;
end;

function TProcessEx.GetOutputStrings: TstringList;
begin
  if (FOutputStrings.Count=0) and (FOutStream.Size>0) then
    begin
    FOutStream.Position := 0;
    FOutputStrings.LoadFromStream(FOutStream);
    end;
  result:=FOutputStrings;
end;

function TProcessEx.GetParametersString: String;
begin
  result:=AnsiReplaceStr(Parameters.text, LineEnding, ' ');
end;

function TProcessEx.GetExceptionInfo: string;
begin
  result:=FExceptionInfoStrings.Text;
end;

function TProcessEx.GetProcessEnvironment: TProcessEnvironment;
begin
  If not assigned(FProcessEnvironment) then
    FProcessEnvironment:=TProcessEnvironment.Create;
  result:=FProcessEnvironment;
end;

procedure TProcessEx.SetOnError(AValue: TErrorFunc);
begin
  if FOnError=AValue then Exit;
  FOnError:=AValue;
end;

procedure TProcessEx.SetOnErrorM(AValue: TErrorMethod);
begin
  if FOnErrorM=AValue then Exit;
  FOnErrorM:=AValue;
end;

procedure TProcessEx.SetOnOutput(AValue: TDumpFunc);
begin
  if FOnOutput=AValue then Exit;
  FOnOutput:=AValue;
end;

procedure TProcessEx.SetOnOutputM(AValue: TDumpMethod);
begin
  if FOnOutputM=AValue then Exit;
  FOnOutputM:=AValue;
end;

procedure TProcessEx.SetParametersString(AValue: String);
begin
  CommandToList(AValue,Parameters);
end;

procedure TProcessEx.Execute;

  function ReadOutput: boolean;

  const
    BufSize = 4096;
  var
    Buffer: array[0..BufSize - 1] of byte;
    ReadBytes: integer;
  begin
    Result := False;
    while Output.NumBytesAvailable > 0 do
    begin
      ReadBytes := Output.Read(Buffer, BufSize);
      FOutStream.Write(Buffer, ReadBytes);
      if Assigned(FOnOutput) then
        FOnOutput(Self,copy(pchar(@buffer[0]),1,ReadBytes));
      if Assigned(FOnOutputM) then
        FOnOutputM(Self,copy(pchar(@buffer[0]),1,ReadBytes));
      Result := True;
    end;
  end;

begin
  try
    // "Normal" linux and DOS exit codes are in the range 0 to 255.
    // Windows System Error Codes are 0 to 15999
    // Use negatives for internal errors.
    FExitStatus:=-1;
    FExceptionInfoStrings.Clear;
    FOutputStrings.Clear;
    FOutStream.Clear;
    if Assigned(FProcessEnvironment) then
      inherited Environment:=FProcessEnvironment.EnvironmentList;
    Options := Options +[poUsePipes, poStderrToOutPut];
    if Assigned(FOnOutput) then
      FOnOutput(Self,'Executing : '+Executable+' '+ ParametersString+' (Working dir: '+ CurrentDirectory +')'+ LineEnding);
    if Assigned(FOnOutputM) then
      FOnOutputM(Self,'Executing : '+Executable+' '+ ParametersString+' (Working dir: '+ CurrentDirectory +')'+ LineEnding);
    inherited Execute;
    while Running do
    begin
      if not ReadOutput then
        Sleep(50);
    end;
    ReadOutput;
    FExitStatus:=inherited ExitStatus;
    if (FExitStatus<>0) and (Assigned(OnError) or Assigned(OnErrorM))  then
      if Assigned(OnError) then
        OnError(Self,false)
      else
        OnErrorM(Self,false);
  except
    on E: Exception do
    begin
    FExceptionInfoStrings.Add('Exception calling '+Executable+' '+Parameters.Text);
    FExceptionInfoStrings.Add('Details: '+E.ClassName+'/'+E.Message);
    FExitStatus:=-2;
    if Assigned(OnError) then
      OnError(Self,true);
    end;
  end;
end;

constructor TProcessEx.Create(AOwner : TComponent);
begin
  inherited;
  FExceptionInfoStrings:= TstringList.Create;
  FOutputStrings:= TstringList.Create;
  FOutStream := TMemoryStream.Create;
end;

destructor TProcessEx.Destroy;
begin
  FExceptionInfoStrings.Free;
  FOutputStrings.Free;
  FOutStream.Free;
  If assigned(FProcessEnvironment) then
    FProcessEnvironment.Free;
  inherited Destroy;
end;

{ TProcessEnvironment }

function TProcessEnvironment.GetVarIndex(VarName: string): integer;
var
  idx:integer;

  function ExtractVar(VarVal:string):string;
  begin
    result:='';
    if length(Varval)>0 then
      begin
      if VarVal[1] = '=' then //windows
        delete(VarVal,1,1);
      result:=trim(copy(VarVal,1,pos('=',VarVal)-1));
      if not FCaseSensitive then
        result:=UpperCase(result);
      end
  end;

begin
  if not FCaseSensitive then
    VarName:=UpperCase(VarName);
  idx:=0;
  while idx<FEnvironmentList.Count  do
    begin
    if VarName = ExtractVar(FEnvironmentList[idx]) then
      break;
    idx:=idx+1;
    end;
  if idx<FEnvironmentList.Count then
    result:=idx
  else
    result:=-1;
end;

function TProcessEnvironment.GetVar(VarName: string): string;
var
  idx:integer;

  function ExtractVal(VarVal:string):string;
  begin
    result:='';
    if length(Varval)>0 then
      begin
      if VarVal[1] = '=' then //windows
        delete(VarVal,1,1);
      result:=trim(copy(VarVal,pos('=',VarVal)+1,length(VarVal)));
      end
  end;

begin
  idx:=GetVarIndex(VarName);
  if idx>0 then
    result:=ExtractVal(FEnvironmentList[idx])
  else
    result:='';
end;

procedure TProcessEnvironment.SetVar(VarName, VarValue: string);
var
  idx:integer;
  s:string;
begin
  idx:=GetVarIndex(VarName);
  s:=trim(Varname)+'='+trim(VarValue);
  if idx>0 then
    FEnvironmentList[idx]:=s
  else
    FEnvironmentList.Add(s);
end;

constructor TProcessEnvironment.Create;
var
  i: integer;
begin
  FEnvironmentList:=TStringList.Create;
  {$ifdef WINDOWS}
  FCaseSensitive:=false;
  {$else}
  FCaseSensitive:=true;
  {$endif WINDOWS}
  // GetEnvironmentVariableCount is 1 based
  for i:=1 to GetEnvironmentVariableCount do
    EnvironmentList.Add(trim(GetEnvironmentString(i)));
end;

destructor TProcessEnvironment.Destroy;
begin
  FEnvironmentList.Free;
  inherited Destroy;
end;


procedure DumpConsole(Sender:TProcessEx; output:string);
begin
  write(output);
end;

function ExecuteCommandHidden(const Executable, Parameters: string; Verbose:boolean): integer;
var
  s:string;
begin
  Result:=ExecuteCommandHidden(Executable, Parameters,s,Verbose);
end;

function ExecuteCommandHidden(const Executable, Parameters: string; var Output: string
  ; Verbose:boolean): integer;
var
  PE:TProcessEx;
begin
  PE:=TProcessEx.Create(nil);
  try
    PE.Executable:=Executable;
    PE.ParametersString:=Parameters;
    PE.ShowWindow := swoHIDE;
    if Verbose then
      PE.OnOutput:=@DumpConsole;
    PE.Execute;
    Output:=PE.OutputString;
    Result:=PE.ExitStatus;
  finally
    PE.Free;
  end;
end;

end.

