-module(player_client).
-export([start/5]).
-export([enter_room/1, leave_room/1, show/1, stop/1]).
-export([get_player/1]).

-record(state, {nickname,
				type,
				player,
				board,
				socket}).
start(NickName, PlayerType, Board, SIp, SPort) ->
	Pid = spawn(fun() -> init(NickName, PlayerType, 
							  Board, SIp, SPort) end),
	{ok, Pid}.

enter_room(Pid) ->
	Pid ! enter_room,
	ok.

leave_room(Pid) ->
	Pid ! leave_room,
	ok.

stop(Pid) ->
	Pid ! stop,
	ok.

show(Pid) ->
	Pid ! show,
	ok.	

get_player(Pid) ->
	call(Pid, get_player).	

call(Pid, Msg) ->
	Ref = make_ref(),
	Pid ! {Msg, Ref, self()},
	receive
		{Ref, Reply} ->
			Reply
	end.	

init(NickName, PlayerType, Board, SIp, SPort) ->
	io:format("connect to ~p~n", [{SIp, SPort}]),
	{ok, Sock} = gen_tcp:connect(SIp, SPort, [binary, {active, true},
													  {packet, 2}]),
	Player = player:start(PlayerType, Board),
	loop(#state{nickname=NickName,
			    type=PlayerType,
			    player=Player,
			    board=Board,
			    socket=Sock}).

loop(State = #state{nickname=NickName,
					type=Type,
					player=Player,
					board=_Board,
					socket=Sock}) ->
	receive
		{echo, Msg} ->
			gen_tcp:send(Sock, term_to_binary({echo, Msg}));
		enter_room ->
			gen_tcp:send(Sock, term_to_binary({enter_room, NickName})),
			loop(State);
		leave_room ->
			gen_tcp:send(Sock, term_to_binary({leave_room, NickName})),
			loop(State);
		stop ->
			player:stop(Type, Player);	
		{get_player, Ref, From} ->
			From ! {Ref, Player},
			loop(State);				
		show ->
			player:show(Type, Player),
			loop(State);
		{tcp, _, TcpData} ->
			case binary_to_term(TcpData) of
				{echo, Msg} ->
					io:format("ECHO: ~p~n", [Msg]);
				{notify, Msg} ->
					io:format("~s~n", [Msg]);
				{update, Move, GameState} ->
					player:update(Type, Player, GameState),
					player:display(Type, Player, GameState, Move);
				stop ->
					player:stop(Type, Player);
				play ->
					{ok, Move} = player:get_move(Type, Player),
					gen_tcp:send(Sock, term_to_binary({play, Move}));
				Unexpected ->
					io:format("client receive unexpected tcp ~p~n", [Unexpected])
			end,
			loop(State)
	end.