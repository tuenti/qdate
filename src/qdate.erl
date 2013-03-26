-module(qdate).

-export([
	to_string/1,
	to_string/2,
	to_string/3,
	to_date/1,
	to_date/2,
	to_now/1,
	to_unixtime/1,
	unixtime/0
]).

-export([
 	register_parser/2,
 	register_parser/1,
	deregister_parser/1,
	deregister_parsers/0,

 	register_format/2,
 	deregister_format/1,

	set_timezone/1,
	set_timezone/2,
	get_timezone/0,
	get_timezone/1,
	clear_timezone/0,
	clear_timezone/1
]).


%% Exported for API compatibility with ec_date
-export([
	format/1,format/2,
	nparse/1,
	parse/1
]).

%% This the value in gregorian seconds for jan 1st 1970, 12am
%% It's used to convert to and from unixtime, since unixtime starts 
%% 1970-01-01 12:00am
-define(UNIXTIME_BASE,62167219200).

%% This is the timezone only if the qdate application variable 
%% "default_timezone" isn't set or is set to undefined.
%% It's recommended that your app sets the var in a config, or at least using
%%
%% 		application:set_env(qdate, default_timezone, "GMT").
%%
-define(DEFAULT_TZ, case application:get_env(qdate, default_timezone) of 
						undefined -> "GMT";
						TZ -> TZ 
					end).

-define(DETERMINE_TZ, determine_timezone()).


to_string(Format) ->
	to_string(Format, now()).

to_string(Format, Date) ->
	to_string(Format, ?DETERMINE_TZ, Date).

to_string(FormatKey, ToTZ, Date) when is_atom(FormatKey) orelse is_tuple(FormatKey) ->
	Format = case qdate_srv:get_format(FormatKey) of
		undefined -> throw({undefined_format_key,FormatKey});
		F -> F
	end,
	to_string(Format, ToTZ, Date);
to_string(Format, ToTZ, Date) when is_binary(Format) ->
	list_to_binary(to_string(binary_to_list(Format), ToTZ, Date));
to_string(Format, ToTZ, Date) when is_list(Format) ->
	ec_date:format(Format,to_date(Date,ToTZ)).

format(Format) ->
	to_string(Format).

format(Format, Date) ->
	to_string(Format, Date).

parse(String) ->
	to_date(String).

nparse(String) ->
	to_now(String).

%% This converts dates without regard to timezone.
%% Unixtime just goes to UTC
raw_to_date(Unixtime) when is_integer(Unixtime) ->
	unixtime_to_date(Unixtime);
raw_to_date(DateString) when is_list(DateString) ->
	ec_date:parse(DateString);
raw_to_date(Now = {_,_,_}) ->
	calendar:now_to_datetime(Now);
raw_to_date(Date = {{_,_,_},{_,_,_}}) ->
	Date.

to_date(RawDate) ->
	to_date(RawDate, ?DETERMINE_TZ).

to_date(RawDate, ToTZKey) when is_atom(ToTZKey) orelse is_tuple(ToTZKey) ->
	case get_timezone(ToTZKey) of
		undefined -> throw({timezone_key_not_found,ToTZKey});
		ToTZ -> to_date(RawDate, ToTZ)
	end;
to_date(RawDate, ToTZ)  ->
	{ExtractedDate, ExtractedTZ} = extract_timezone(RawDate),
	{RawDate3, FromTZ} = case try_registered_parsers(RawDate) of
		undefined ->
			{ExtractedDate, ExtractedTZ};
		{ParsedDate,undefined} ->
			{ParsedDate,ExtractedTZ};
		{ParsedDate,ParsedTZ} ->
			{ParsedDate,ParsedTZ}
	end,	
	Date = raw_to_date(RawDate3),
	localtime:local_to_local(Date,FromTZ,ToTZ).

try_registered_parsers(RawDate) ->
	Parsers = qdate_srv:get_parsers(),
	try_parsers(RawDate,Parsers).
	
try_parsers(_RawDate,[]) ->
	undefined;
try_parsers(RawDate,[{ParserKey,Parser}|Parsers]) ->
	try Parser(RawDate) of
		{{_,_,_},{_,_,_}} = DateTime ->
			{DateTime,undefined};
		{DateTime={{_,_,_},{_,_,_}},Timezone} ->
			{DateTime,Timezone};
		undefined ->
			try_parsers(RawDate, Parsers);
		Other ->
			throw({invalid_parser_return_value,[{parser_key,ParserKey},{return,Other}]})
	catch
		Error:Reason -> 
			throw({error_in_parser,[{error,{Error,Reason}},{parser_key,ParserKey}]})
	end.

set_timezone(TZ) ->
	qdate_srv:set_timezone(TZ).

set_timezone(Key,TZ) ->
	qdate_srv:set_timezone(Key, TZ).

get_timezone() ->
	qdate_srv:get_timezone().

get_timezone(Key) ->
	qdate_srv:get_timezone(Key).

clear_timezone() ->
	qdate_srv:clear_timezone().

clear_timezone(Key) ->
	qdate_srv:clear_timezone(Key).

extract_timezone(Unixtime) when is_integer(Unixtime) ->
	{Unixtime, ?DETERMINE_TZ};
extract_timezone(DateString) when is_list(DateString) ->
	AllTimezones = localtime:list_timezones(),
	RevDate = lists:reverse(DateString),
	extract_timezone_helper(RevDate, AllTimezones);
extract_timezone(Date={{_,_,_},{_,_,_}}) ->
	{Date, ?DETERMINE_TZ};
extract_timezone(Now={_,_,_}) ->
	{Now, ?DETERMINE_TZ};
extract_timezone({MiscDate,TZ}) ->
	{MiscDate,TZ}.
	
extract_timezone_helper(RevDate, []) ->
	{lists:reverse(RevDate), ?DETERMINE_TZ};
extract_timezone_helper(RevDate, [TZ | TZs]) ->
	RevTZ = lists:reverse(TZ),
	case lists:split(length(TZ),RevDate) of
		{RevTZ," " ++ Remainder} ->
			{lists:reverse(Remainder), TZ};
		_ ->
			extract_timezone_helper(RevDate, TZs)
	end.

determine_timezone() ->
	case qdate_srv:get_timezone() of
		undefined -> ?DEFAULT_TZ;
		TZ -> TZ
	end.

to_unixtime(Unixtime) when is_integer(Unixtime) ->
	Unixtime;
to_unixtime({MegaSecs,Secs,_}) ->
	MegaSecs*1000000 + Secs;
to_unixtime(ToParse) ->
	Date = to_date(ToParse),
	calendar:datetime_to_gregorian_seconds(Date) - ?UNIXTIME_BASE.

unixtime() ->
	to_unixtime(now()).

to_now(Now = {_,_,_}) ->
	Now;
to_now(ToParse) ->
	Unixtime = to_unixtime(ToParse),
	unixtime_to_now(Unixtime).


register_parser(Key, Parser) when is_function(Parser,1) ->
	qdate_srv:register_parser(Key,Parser).

register_parser(Parser) when is_function(Parser,1) ->
	qdate_srv:register_parser(Parser).

deregister_parser(Key) ->
	qdate_srv:deregister_parser(Key).

deregister_parsers() ->
	qdate_srv:deregister_parsers().

register_format(Key, Format) ->
	qdate_srv:register_format(Key, Format).

deregister_format(Key) ->
	qdate_srv:deregister_format(Key).



unixtime_to_now(T) when is_integer(T) ->
	MegaSec = floor(T/1000000),
	Secs = T - MegaSec*1000000,
	{MegaSec,Secs,0}.

unixtime_to_date(T) ->
	Now = unixtime_to_now(T),
	calendar:now_to_datetime(Now).

floor(N) when N >= 0 ->
	trunc(N);
floor(N) when N < 0 ->
	Int = trunc(N),
	if
		Int==N -> Int;
		true -> Int-1
	end.

tz_formatting(Date,Format,TZ) ->
	%% e, I, O, P, and T, Z
	%% e = "UTC, GMT, Atlantic,/Azores"
	%% I = Daylight Saving on = 1, off = 0
	%% O = GMT diff in hours: +0200
	%% P = GMT diff in hours with color: +02:00
	%% T = TZ abbreviation: EST, MDT
	%% Z = TZ offset in seconds: -43200 - 50400
	not_implemented.



%% TESTS
-include_lib("eunit/include/eunit.hrl").

%% emulates as if a forum-type website has a Site tz, and a user-specified tz
-define(SITE_TZ,"PST").
-define(USER_TZ,"CST").
-define(SELF_TZ,"EST"). %% Self will be the pid of the current running process
-define(SITE_KEY,test_site_key).
-define(USER_KEY,test_user_key).



tz_test_() ->
	{
		setup,
		fun start_test/0,
		fun stop_test/1,
		fun(SetupData) ->
			{inorder,[
				simple_test(SetupData),
				tz_tests(SetupData),
				test_process_die(SetupData),
				parser_format_test(SetupData)
			]}
		end
	}.

tz_tests(_) ->
	{inorder,[
		?_assertEqual(ok,set_timezone(?SELF_TZ)),
		?_assertEqual(?SELF_TZ,get_timezone()),
		?_assertEqual(?USER_TZ,get_timezone(?USER_KEY)),
		?_assertEqual(?SITE_TZ,get_timezone(?SITE_KEY)),
		?_assertEqual({{2013,3,7},{0,0,0}}, to_date("3/7/2013 1:00am EST",?USER_KEY)),
		?_assertEqual({{2013,3,7},{0,0,0}}, to_date("3/7/2013 3:00am EST",?SITE_KEY)),
		?_assertEqual({{2013,3,7},{2,0,0}}, to_date("3/7/2013 1:00am CST")) %% will use the current pid's setting
	]}.

simple_test(_) ->
	{inorder,[
		?_assertEqual(ok,clear_timezone()),
		?_assertEqual(0,to_unixtime({0,0,0})),
		?_assertEqual({0,0,0},to_now(0)),
		?_assertEqual(0,to_unixtime("1970-01-01 12:00am GMT")),
		?_assertEqual(21600,to_unixtime("1970-01-01 12:00am CST")),
		?_assertEqual(0,to_unixtime({{1970,1,1},{0,0,0}})),
		?_assertEqual({{1970,1,1},{0,0,0}},to_date(0)),
		?_assertEqual({{2013,3,7},{0,0,0}},to_date(to_unixtime("2013-03-07 12am"))),
		?_assertEqual("2012-12-01 1:00pm", to_string("Y-m-d g:ia","EST","2012-12-01 12:00pm CST")),
		?_assertEqual(to_unixtime("2012-01-01 12:00pm CST"), to_unixtime("2012-01-01 10:00am PST")),
		?_assertEqual({{2012,12,31},{18,15,15}},to_date("Dec 31, 2012 6:15:15pm")),
		?_assertEqual({{2013,1,1},{0,15,15}},to_date("December 31, 2012 6:15:15pm CST","GMT"))
	]}.

%%tz_char_tests(_) ->
%%	qdate:set_timezone(?SELF_TZ),

parser_format_test(_) ->
	{inorder,[
		?_assertEqual({{2008,2,8},{0,0,0}},to_date("20080208")),
		?_assertThrow({ec_date,{bad_date,_}},to_date("20111232")),	%% invalid_date with custom format
		?_assertEqual("2/8/2008",to_string(shortdate,{{2008,2,8},{0,0,0}})),
		?_assertEqual("2/8/2008",to_string(shortdate,"20080208")), %% both regged format and parser
		?_assertEqual("2/8/2008 12:00am",to_string(longdate,"2008-02-08 12:00am")),
		?_assertEqual("2/8/2008 12:00am",to_string(longdate,"20080208"))
	]}.

test_process_die(_) ->
	TZ = "MST",
	Caller = self(),
	Pid = spawn(fun() -> 
						set_timezone(TZ),
						Caller ! tz_set,
						receive tz_set_ack -> ok end,
						Caller ! get_timezone()
				end),

	PidTZFromOtherProc = receive 
							tz_set ->
								T = get_timezone(Pid),
								Pid ! tz_set_ack,
								T
							after 1000 -> fail 
						 end,
	ReceivedTZ = receive 
					TZ -> TZ 
				 after 2000 ->
					fail 
				 end,

	[
		%% Verify we can read the spawned process's TZ from another proc
		?_assertEqual(TZ,PidTZFromOtherProc),
		%% Verify the spawned process properly set the TZ
		?_assertEqual(TZ,ReceivedTZ),
		%% Verify the now-dead spawned process's TZ is cleared
		?_assertEqual(undefined,get_timezone(Pid))
	].
	
		
start_test() ->
	application:start(qdate),
	set_timezone(?SELF_TZ),
	set_timezone(?SITE_KEY,?SITE_TZ),
	set_timezone(?USER_KEY,?USER_TZ),
	register_parser(compressed,fun compressed_parser/1),
	register_parser(microsoft_date,fun microsoft_parser/1),
	register_format(shortdate,"n/j/Y"),
	register_format(longdate,"n/j/Y g:ia").

compressed_parser(List) when length(List)==8 ->
	try re:run(List,"^(\\d{4})(\\d{2})(\\d{2})$",[{capture,all_but_first,list}]) of
		nomatch -> undefined;
		{match, [Y,M,D]} -> 
			Date = {list_to_integer(Y),list_to_integer(M),list_to_integer(D)},
			case calendar:valid_date(Date) of
				true ->
					{Date,{0,0,0}};
				false -> undefined
			end
	catch
		_:_ -> undefined
	end;
compressed_parser(_) -> 
	undefined.

microsoft_parser(FloatDate) when is_float(FloatDate) ->
	try
		DaysSince1900 = floor(FloatDate),
		Days0to1900 = calendar:date_to_gregorian_days(1900,1,1),
		GregorianDays = Days0to1900 + DaysSince1900,
		Date = calendar:gregorian_days_to_date(GregorianDays),
		Seconds = round(86400 * (FloatDate - DaysSince1900)),
		Time = calendar:seconds_to_time(Seconds),
		{Date,Time}
	catch
		_:_ -> undefined
	end;
microsoft_parser(_) ->
	undefined.

	

stop_test(_) ->
	ok.
