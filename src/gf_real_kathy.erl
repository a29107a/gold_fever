-module(gf_real_kathy).
-author('elbrujohalcon@inaka.net').

-behaviour(gen_server).

%%% gen_server callbacks
-export([
         init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3
        ]).
-export([start_link/0, token/1, delete_token/1]).

-record(state, { tokens :: #{string() => node()}
               , callers :: [pid()]
               }).
-type state() :: #state{}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% External API functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start_link() -> {ok, pid()}.
start_link() ->
  gen_server:start_link(
    {local, kathy}, ?MODULE, noargs, [{debug, [trace, log]}]).

-spec token(node()) -> string().
token(Node) -> gen_server:call(kathy, {token, Node}).

-spec delete_token(node()) -> ok.
delete_token(Node) -> gen_server:cast(kathy, {delete_token, Node}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Callback implementation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init(noargs) -> {ok, state()}.
init(noargs) ->
  {ok, #state{callers = [], tokens = #{}}}.

-spec handle_call(term(), term(), state()) -> {reply, term(), state()}.
handle_call({token, Node}, _From, State) ->
  Tokens = State#state.tokens,
  Token = base64:encode(crypto:hash(md5, term_to_binary(Node))),
  {reply, Token, State#state{tokens = maps:put(Token, Node, Tokens)}};
handle_call(#{token := Token}, From, State) ->
  handle_call(Token, From, State);
handle_call(Token, {Caller, _}, State) ->
  {Welcome, NewCallers} =
    case lists:member(Caller, State#state.callers) of
      true -> {gold_fever:get_config(step7, again), State#state.callers};
      false ->
        {gold_fever:get_config(step7, welcome), [Caller|State#state.callers]}
    end,
  CallerNode = node(Caller),
  MessageResponse =
    { gold_fever:get_config(step7, message)
    , maps:put(Token, Caller, State#state.tokens)
    },
  {Message, NewTokens} =
    case maps:get(Token, State#state.tokens, notfound) of
      Caller ->
        send_image(Caller),
        {gold_fever:get_config(step7, message), State#state.tokens};
      CallerNode -> MessageResponse;
      notfound -> {gold_fever:get_config(step7, badauth), State#state.tokens};
      OtherPid when is_pid(OtherPid) ->
        case node(OtherPid) of
          CallerNode -> MessageResponse;
          _OtherNode ->
            {gold_fever:get_config(step7, expired), State#state.tokens}
        end;
      _OtherNode -> {gold_fever:get_config(step7, expired), State#state.tokens}
    end,
  FinalMsg = Welcome ++ " - " ++ Message,
  {reply, FinalMsg, State#state{tokens = NewTokens, callers = NewCallers}}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({delete_token, Node}, State) ->
  ListOfTokens = maps:to_list(State#state.tokens),
  NewListOfTokens = [{T, N} || {T, N} <- ListOfTokens, N /= Node],
  {noreply, State#state{tokens = maps:from_list(NewListOfTokens)}};
handle_cast(_Cast, State) -> {noreply, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Unused Callbacks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(_Info, State) -> {noreply, State}.
-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) -> ok.
-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Internal Functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
send_image(Caller) ->
  Filename = gold_fever:get_config(step7, image),
  {ok, Body} = file:read_file(Filename),
  Caller ! Body.
