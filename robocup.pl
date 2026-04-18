:- use_module(library(lists)).
:- use_module(library(random)).

% ------------------------------------------------------------------
% 1. KNOWLEDGE REPRESENTATION
% ------------------------------------------------------------------
goal_target(team1, 100, 25).
goal_target(team2, 0,   25).

in_shoot_range(team1, X) :- X >= 80.
in_shoot_range(team2, X) :- X =< 20.

pass_cooldown(12).
shot_cooldown(20).

% Dynamic Formations: formation_target(Team, Role, PossessionTeam, TargetX)
% TEAM 1 (Attacks Right)
formation_target(team1, defender, team1, 45).   % Attacking: Push high
formation_target(team1, defender, team2, 18).   % Defending: Drop deep
formation_target(team1, midfielder, team1, 65). % Attacking
formation_target(team1, midfielder, team2, 35). % Defending
formation_target(team1, forward, team1, 80).    % Attacking
formation_target(team1, forward, team2, 50).    % Defending: Stay up for counter

% TEAM 2 (Attacks Left)
formation_target(team2, defender, team2, 55).   % Attacking: Push high
formation_target(team2, defender, team1, 82).   % Defending: Drop deep
formation_target(team2, midfielder, team2, 35). % Attacking
formation_target(team2, midfielder, team1, 65). % Defending
formation_target(team2, forward, team2, 20).    % Attacking
formation_target(team2, forward, team1, 50).    % Defending: Stay up for counter

% ------------------------------------------------------------------
% 2. DYNAMIC STATE
% ------------------------------------------------------------------
:- dynamic(ball/2).
:- dynamic(player/5).
:- dynamic(score/2).
:- dynamic(game_over/1).
:- dynamic(tick/1).
:- dynamic(paused_until/1).
:- dynamic(pending_reset/2).
:- dynamic(possession/1).
:- dynamic(carrier/2).
:- dynamic(cooldown/1).
:- dynamic(stat/2).

% ------------------------------------------------------------------
% 3. RESET / INITIALISATION
% ------------------------------------------------------------------
reset_game :-
    retractall(ball(_,_)), retractall(player(_,_,_,_,_)),
    retractall(score(_,_)), retractall(game_over(_)),
    retractall(tick(_)),   retractall(paused_until(_)),
    retractall(pending_reset(_,_)),
    retractall(possession(_)), retractall(carrier(_,_)),
    retractall(cooldown(_)),   retractall(stat(_,_)),
    assertz(tick(0)), assertz(paused_until(0)), assertz(cooldown(0)),
    assertz(ball(pos(50,25), vel(0,0))),
    assertz(score(team1, 0)), assertz(score(team2, 0)),
    assertz(stat(shots, 0)), assertz(stat(passes, 0)),
    assertz(stat(tackles, 0)), assertz(stat(saves, 0)),
    reset_positions(team1).

reset_positions(KickTeam) :-
    retractall(player(_,_,_,_,_)),
    retractall(carrier(_,_)), retractall(possession(_)),
    retractall(cooldown(_)), assertz(cooldown(0)),
    assertz(possession(KickTeam)),
    assertz(carrier(KickTeam, forward)),
    (KickTeam == team1 ->
        assertz(player(team1, forward, pos(50,25), 100, idle))
    ;   assertz(player(team1, forward, pos(38,22), 100, idle))
    ),
    assertz(player(team1, midfielder, pos(32,28), 100, idle)),
    assertz(player(team1, defender,   pos(18,22), 100, idle)),
    assertz(player(team1, goalkeeper, pos(5, 25),  100, idle)),
    (KickTeam == team2 ->
        assertz(player(team2, forward, pos(50,25), 100, idle))
    ;   assertz(player(team2, forward, pos(62,28), 100, idle))
    ),
    assertz(player(team2, midfielder, pos(68,22), 100, idle)),
    assertz(player(team2, defender,   pos(82,28), 100, idle)),
    assertz(player(team2, goalkeeper, pos(95,25),  100, idle)).

% ------------------------------------------------------------------
% 4. HELPERS
% ------------------------------------------------------------------
limit(V, L, H, O) :- O is max(L, min(H, V)).

normalize(DX, DY, NX, NY) :-
    D is sqrt(DX*DX + DY*DY),
    (D > 0.001 -> NX is DX/D, NY is DY/D ; NX = 0, NY = 0).

pdist(X1, Y1, X2, Y2, D) :-
    D is sqrt((X2-X1)*(X2-X1) + (Y2-Y1)*(Y2-Y1)).

nearest_to_ball(Team, Role) :-
    ball(pos(BX,BY), _),
    findall(D-R,
        (player(Team, R, pos(PX,PY), _, _), R \= goalkeeper,
         D is sqrt((BX-PX)*(BX-PX)+(BY-PY)*(BY-PY))),
        Ds),
    Ds \= [],
    keysort(Ds, [_-Role|_]).

sep(PX, PY, SDX, SDY) :-
    findall(D-oy(OY),
        (player(_,_,pos(OX,OY),_,_),
         (OX \= PX ; OY \= PY),
         D is sqrt((OX-PX)*(OX-PX)+(OY-PY)*(OY-PY)), D < 8),
        Ds),
    (Ds \= [] ->
        keysort(Ds, [MD-oy(MY)|_]),
        (MD < 5 -> (PY > MY -> SDY = 0.5 ; SDY = -0.5), SDX = 0
                 ; SDX = 0, SDY = 0)
    ;   SDX = 0, SDY = 0).

upd_stam(S, Spd, NS, State, OutState) :-
    (Spd >= 0.6 ->
        Delta = -0.5
    ; Spd >= 0.4 ->
        Delta = -0.3
    ;
        Delta = 0.20
    ),
    TempS is S + Delta,
    (TempS > 100 -> ClampS = 100 ; TempS < 0 -> ClampS = 0 ; ClampS = TempS),
    NS = ClampS,
    (NS =:= 0 ->
        OutState = exhausted
    ; NS >= 30, State == exhausted ->
        OutState = normal
    ;
        OutState = State
    ).

bump(Name) :-
    stat(Name, V), NV is V+1,
    retract(stat(Name, V)), assertz(stat(Name, NV)).

step_toward(Team, Role, PX, PY, TX, TY, S, St, Spd) :-
    Dist is sqrt((TX-PX)*(TX-PX) + (TY-PY)*(TY-PY)),
    (Dist < 1.2 ->
        upd_stam(S, 0, NS, St, NSt),
        retract(player(Team,Role,_,_,_)),
        assertz(player(Team,Role,pos(PX,PY),NS,NSt))
    ;
        normalize(TX-PX, TY-PY, NX, NY),
        sep(PX, PY, SDX, SDY),
        NX2 is PX + (NX + SDX*0.2)*Spd,
        NY2 is PY + (NY*0.9 + SDY*0.2)*Spd,
        limit(NX2, 1, 99, CX), limit(NY2, 1, 49, CY),
        upd_stam(S, Spd, NS, St, NSt),
        retract(player(Team,Role,_,_,_)),
        assertz(player(Team,Role,pos(CX,CY),NS,NSt))
    ).

% ------------------------------------------------------------------
% 5. ACTIONS
% ------------------------------------------------------------------
do_shoot(T, Role, PX, PY, S) :-
    carrier(T, Role), !,
    goal_target(T, GX, _),
    random_between(17, 33, TY),
    normalize(GX-PX, TY-PY, NX, NY),
    random(Rnd), ShotSpd is 3.5 + (Rnd * 2.0),
    VX is NX*ShotSpd, VY is NY*ShotSpd,
    shot_cooldown(CD),
    retractall(carrier(_,_)),
    retractall(cooldown(_)), assertz(cooldown(CD)),
    retract(ball(_,_)), assertz(ball(pos(PX,PY), vel(VX,VY))),
    NS is max(0, S-4),
    retract(player(T,Role,_,_,_)), assertz(player(T,Role,pos(PX,PY),NS,shooting)),
    bump(shots).

do_pass(T, From, To, PX, PY, S) :-
    carrier(T, From), !,
    player(T, To, pos(TX,TY), _, _), From \= To,
    normalize(TX-PX, TY-PY, NX, NY),
    Dist is sqrt((TX-PX)*(TX-PX)+(TY-PY)*(TY-PY)),
    PassSpd is min(3.5, max(1.8, Dist*0.10)),
    VX is NX*PassSpd, VY is NY*PassSpd,
    pass_cooldown(CD),
    retractall(carrier(_,_)),
    retractall(cooldown(_)), assertz(cooldown(CD)),
    retract(ball(_,_)), assertz(ball(pos(PX,PY), vel(VX,VY))),
    NS is max(0, S-2),
    retract(player(T,From,_,_,_)), assertz(player(T,From,pos(PX,PY),NS,passing)),
    bump(passes).

do_dribble(T, Role, PX, PY, S, St, Spd, Tick) :-
    carrier(T, Role), !,
    goal_target(T, GX, GY),
    normalize(GX-PX, GY-PY, BaseNX, BaseNY),
    execute_dribble_vector(T, Role, PX, PY, BaseNX, BaseNY, S, St, Spd, Tick).

do_dribble_to(T, Role, PX, PY, TargX, TargY, S, St, Spd, Tick) :-
    carrier(T, Role), !,
    normalize(TargX-PX, TargY-PY, BaseNX, BaseNY),
    execute_dribble_vector(T, Role, PX, PY, BaseNX, BaseNY, S, St, Spd, Tick).

execute_dribble_vector(T, Role, PX, PY, BaseNX, BaseNY, S, St, Spd, Tick) :-
    (T == team1 -> Opp = team2 ; Opp = team1),
    findall(D-pos(OX,OY,Dot),
        (player(Opp, _, pos(OX,OY), _, _),
         D is sqrt((OX-PX)*(OX-PX) + (OY-PY)*(OY-PY)), D < 15,
         normalize(OX-PX, OY-PY, OppNX, OppNY),
         Dot is (BaseNX * OppNX) + (BaseNY * OppNY), Dot > 0.1),
        Threats),
    keysort(Threats, SortedThreats),
    (SortedThreats = [MinD-pos(OX, OY, Dot)|_] ->
        normalize(OX-PX, OY-PY, OppNX, OppNY),
        PerpX is -BaseNY, PerpY is BaseNX,
        Side is (OppNX * PerpX) + (OppNY * PerpY),
        (Side >= 0 -> CutNX is -PerpX, CutNY is -PerpY ; CutNX is PerpX, CutNY is PerpY),
        JukePower is (8.0 / (MinD + 1.0)) * Dot,
        RawNX is BaseNX + (CutNX * JukePower),
        RawNY is BaseNY + (CutNY * JukePower)
    ;
        RawNX = BaseNX, RawNY = BaseNY
    ),
    findall(TD-pos(TX,TY),
        (player(T, _, pos(TX,TY), _, _), (TX \= PX ; TY \= PY),
         TD is sqrt((TX-PX)*(TX-PX) + (TY-PY)*(TY-PY)), TD < 5),
        Teammates),
    keysort(Teammates, SortedMates),
    (SortedMates = [MinTD-pos(TX,TY)|_] ->
        normalize(PX-TX, PY-TY, RepNX, RepNY),
        RepPower is 2.0 / (MinTD + 1.0),
        RawNX2 is RawNX + (RepNX * RepPower),
        RawNY2 is RawNY + (RepNY * RepPower)
    ;
        RawNX2 = RawNX, RawNY2 = RawNY
    ),
    normalize(RawNX2, RawNY2, NX, NY),
    Wander is sin(Tick*0.06 + PY*0.1) * 0.15,
    NX2 is PX + NX * Spd * 0.85,
    NY2 is PY + (NY + Wander) * Spd * 0.85,
    limit(NX2, 1, 99, CX), limit(NY2, 1, 49, CY),
    upd_stam(S, Spd, NS, St, _),
    retract(ball(_,_)), assertz(ball(pos(CX,CY), vel(0,0))),
    retract(player(T,Role,_,_,_)), assertz(player(T,Role,pos(CX,CY),NS,dribbling)).

do_tackle(T, Role, PX, PY, S, St, Spd, OX, OY) :-
    pdist(PX, PY, OX, OY, D),
    (D < 3.2 ->
        random(R),
        TackleChance is 0.35 + (S / 250.0),
        (R < TackleChance ->
            retractall(carrier(_,_)), assertz(carrier(T, Role)),
            retractall(possession(_)), assertz(possession(T)),
            retractall(cooldown(_)), assertz(cooldown(0)),
            retract(ball(_,_)), assertz(ball(pos(PX,PY), vel(0,0))),
            retract(player(T,Role,_,_,_)), assertz(player(T,Role,pos(PX,PY),S,tackling)),
            bump(tackles)
        ;
            step_toward(T, Role, PX, PY, OX, OY, S, St, Spd*0.8)
        )
    ;
        step_toward(T, Role, PX, PY, OX, OY, S, St, Spd)
    ).

% ------------------------------------------------------------------
% 6. AI BEHAVIORS
% ------------------------------------------------------------------

% ---- FORWARD ----
ai_behavior(T, forward) :-
    player(T, forward, pos(PX,PY), S, St),
    tick(Tick), Spd = 0.70,
    (T == team1 -> Opp = team2 ; Opp = team1),
    possession(Poss),
    formation_target(T, forward, Poss, TargetX),
    ball(pos(BX,BY), _),
    (Poss == T ->
        RawY is 25 + (BY - 25) * 1.5, limit(RawY, 8, 42, TargetY)
    ;
        TargetY is 25 + (BY - 25) * 0.6
    ),
    (carrier(T, forward) ->
        (in_shoot_range(T, PX) ->
            do_shoot(T, forward, PX, PY, S)
        ;
            do_dribble(T, forward, PX, PY, S, St, Spd, Tick)
        )
    ; carrier(T, _) ->
        step_toward(T, forward, PX, PY, TargetX, TargetY, S, St, Spd*0.65)
    ; carrier(Opp, OppRole), player(Opp, OppRole, pos(CX,CY), _, _) ->
        step_toward(T, forward, PX, PY, CX, CY, S, St, Spd*0.9)
    ;
        (nearest_to_ball(T, forward) ->
            step_toward(T, forward, PX, PY, BX, BY, S, St, Spd)
        ;
            step_toward(T, forward, PX, PY, TargetX, TargetY, S, St, Spd*0.45)
        )
    ).

% ---- MIDFIELDER ----
ai_behavior(T, midfielder) :-
    player(T, midfielder, pos(PX,PY), S, St),
    tick(Tick), Spd = 0.60,
    (T == team1 -> Opp = team2, ChaseLimit = 52 ; Opp = team1, ChaseLimit = 48),
    possession(Poss),
    formation_target(T, midfielder, Poss, TargetX),
    ball(pos(BX,BY), _),
    (Poss == T ->
        RawY is 25 + (25 - BY) * 0.9, limit(RawY, 10, 40, TargetY)
    ;
        TargetY is 25 + (BY - 25) * 0.5
    ),
    (carrier(T, midfielder) ->
        (player(T, forward, pos(FX,_), _, _),
         (T == team1 -> FX >= 56 ; FX =< 44) ->
            do_pass(T, midfielder, forward, PX, PY, S)
        ; (T == team1, PX < 48 ; T == team2, PX > 52) ->
            (T == team1 -> AdvX = 52 ; AdvX = 48),
            do_dribble_to(T, midfielder, PX, PY, AdvX, 25, S, St, Spd, Tick)
        ;
            do_dribble(T, midfielder, PX, PY, S, St, Spd, Tick)
        )
    ; carrier(T, _) ->
        step_toward(T, midfielder, PX, PY, TargetX, TargetY, S, St, Spd*0.55)
    ; carrier(Opp, OppRole), player(Opp, OppRole, pos(CX,CY), _, _) ->
        ((T == team1, BX =< ChaseLimit ; T == team2, BX >= ChaseLimit) ->
            do_tackle(T, midfielder, PX, PY, S, St, Spd*0.85, CX, CY)
        ;
            step_toward(T, midfielder, PX, PY, TargetX, TargetY, S, St, Spd*0.6)
        )
    ;
        (nearest_to_ball(T, midfielder), (T == team1 -> BX =< ChaseLimit ; BX >= ChaseLimit) ->
            step_toward(T, midfielder, PX, PY, BX, BY, S, St, Spd)
        ;
            step_toward(T, midfielder, PX, PY, TargetX, TargetY, S, St, Spd*0.45)
        )
    ).

% ---- DEFENDER ----
ai_behavior(T, defender) :-
    player(T, defender, pos(PX,PY), S, St),
    Spd = 0.55,
    (T == team1 -> Opp = team2, OwnGoalX = 0, DefLimit = 54
    ;              Opp = team1, OwnGoalX = 100, DefLimit = 46),
    possession(Poss),
    formation_target(T, defender, Poss, TargetX),
    ball(pos(BX,BY), _),
    TargetY is 25 + (BY - 25) * 0.4,
    (carrier(T, defender) ->
        do_pass(T, defender, midfielder, PX, PY, S)
    ; carrier(T, _) ->
        step_toward(T, defender, PX, PY, TargetX, TargetY, S, St, Spd*0.4)
    ; carrier(Opp, OppRole),
      player(Opp, OppRole, pos(CX,CY), _, _) ->
        ((T == team1, CX =< DefLimit ; T == team2, CX >= DefLimit) ->
            do_tackle(T, defender, PX, PY, S, St, Spd, CX, CY)
        ;
            (player(Opp, forward, pos(OFX,OFY), _, _) ->
                MarkX is OFX * 0.3 + TargetX * 0.7,
                MarkY is OFY * 0.5 + TargetY * 0.5,
                step_toward(T, defender, PX, PY, MarkX, MarkY, S, St, Spd*0.5)
            ;
                step_toward(T, defender, PX, PY, TargetX, TargetY, S, St, Spd*0.45)
            )
        )
    ;
        ((T == team1, BX =< 52 ; T == team2, BX >= 48),
         nearest_to_ball(T, defender) ->
            step_toward(T, defender, PX, PY, BX, BY, S, St, Spd)
        ;
            (player(Opp, forward, pos(OFX,OFY), _, _) ->
                MarkX is OFX * 0.3 + TargetX * 0.7,
                MarkY is OFY * 0.5 + TargetY * 0.5,
                step_toward(T, defender, PX, PY, MarkX, MarkY, S, St, Spd*0.5)
            ;
                step_toward(T, defender, PX, PY, TargetX, TargetY, S, St, Spd*0.4)
            )
        )
    ).

% ---- GOALKEEPER ----
ai_behavior(T, goalkeeper) :-
    player(T, goalkeeper, pos(PX,PY), S, St),
    (T == team1 ->
        Opp = team2, GoalX = 0, MinX = 1, MaxX = 18, StandX = 5
    ;
        Opp = team1, GoalX = 100, MinX = 82, MaxX = 99, StandX = 95
    ),
    (carrier(T, goalkeeper) ->
        (player(T, midfielder, pos(_,_), _, _) ->
            do_pass(T, goalkeeper, midfielder, PX, PY, S)
        ; player(T, defender, pos(_,_), _, _) ->
            do_pass(T, goalkeeper, defender, PX, PY, S)
        ;
            do_shoot(T, goalkeeper, PX, PY, S)
        )
    ; carrier(Opp, OppRole),
      player(Opp, OppRole, pos(CX,CY), _, _),
      CX >= MinX, CX =< MaxX, CY >= 10, CY =< 40 ->
        do_tackle(T, goalkeeper, PX, PY, S, St, 0.85, CX, CY)
    ;
        ball(pos(BX,BY), _),
        (BX >= MinX, BX =< MaxX, BY >= 10, BY =< 40 ->
            step_toward(T, goalkeeper, PX, PY, BX, BY, S, St, 0.85)
        ;
            TrackY is 25 + ((BY - 25) * 0.45),
            limit(TrackY, 17, 33, BaseY),
            tick(Tick),
            WanderY is BaseY + sin(Tick * 0.15) * 0.6,
            step_toward(T, goalkeeper, PX, PY, StandX, WanderY, S, St, 0.6)
        )
    ).

% ------------------------------------------------------------------
% 7. BALL PHYSICS
% ------------------------------------------------------------------
update_ball :-
    ball(pos(_,_), vel(0,0)), !.
update_ball :-
    ball(pos(X,Y), vel(VX,VY)),
    NX is X + VX, NY is Y + VY,
    ( (NY < 0 ; NY > 50 ; (NX < 0, (NY =< 16 ; NY >= 34)) ; (NX > 100, (NY =< 16 ; NY >= 34))) ->
        limit(NX, 1, 99, CX), limit(NY, 1, 49, CY),
        retract(ball(_,_)), assertz(ball(pos(CX,CY), vel(0,0))),
        retractall(carrier(_,_)), retractall(cooldown(_)), assertz(cooldown(0))
    ;
        Speed is sqrt(VX*VX + VY*VY),
        (Speed > 2.0 -> Fric = 0.935 ; Fric = 0.962),
        NVX is VX*Fric, NVY is VY*Fric,
        (abs(NVX) < 0.05, abs(NVY) < 0.05 -> FVX=0, FVY=0 ; FVX=NVX, FVY=NVY),
        limit(NX,0,100,CX), limit(NY,1,49,CY),
        retract(ball(_,_)), assertz(ball(pos(CX,CY), vel(FVX,FVY)))
    ).

% ------------------------------------------------------------------
% 8. COOLDOWN TICK + LOOSE-BALL PICKUP
% ------------------------------------------------------------------
tick_cooldown :-
    cooldown(N), N > 0, !,
    N1 is N-1, retractall(cooldown(_)), assertz(cooldown(N1)).
tick_cooldown.

try_pickup :-
    carrier(_, _), !.
try_pickup :-
    cooldown(N), N > 0, !.
try_pickup :-
    ball(pos(BX,BY), _),
    findall(D-p(T,R,PX,PY),
        (player(T, R, pos(PX,PY), _, _),
         D is sqrt((BX-PX)*(BX-PX)+(BY-PY)*(BY-PY)),
         D < 2.8),
        All),
    All \= [], !,
    keysort(All, [_-p(PT,PR,PPX,PPY)|_]),
    retractall(carrier(_,_)), assertz(carrier(PT, PR)),
    retractall(possession(_)), assertz(possession(PT)),
    retractall(cooldown(_)),   assertz(cooldown(0)),
    retract(ball(_,_)), assertz(ball(pos(PPX,PPY), vel(0,0))).
try_pickup.

% ------------------------------------------------------------------
% 9. GOAL DETECTION + SAVE MECHANIC
% ------------------------------------------------------------------
process_goals :-
    ball(pos(X,Y), _),
    (X > 99, Y > 20, Y < 30 -> attempt_save(team2, team1)
    ; X <  1, Y > 20, Y < 30 -> attempt_save(team1, team2)
    ; true).

attempt_save(DefTeam, ScoringTeam) :-
    ball(pos(BX,BY), vel(VX,VY)),
    player(DefTeam, goalkeeper, pos(GKX,GKY), _, _),
    GKDist is sqrt((BX-GKX)*(BX-GKX)+(BY-GKY)*(BY-GKY)),
    BallSpd is sqrt(VX*VX+VY*VY),
    DistFactor is max(0.0, 1.0 - GKDist/16.0),
    SpdPenalty is min(0.55, BallSpd*0.07),
    SaveProb is max(0.04, DistFactor*0.82 - SpdPenalty),
    random(R),
    (R < SaveProb ->
        random(Rj), Jitter is (Rj-0.5)*1.0,
        NVX is -VX*0.42, NVY is Jitter*0.5,
        retract(ball(_,_)), assertz(ball(pos(BX,BY), vel(NVX,NVY))),
        retractall(carrier(_,_)), assertz(carrier(DefTeam, goalkeeper)),
        retractall(possession(_)), assertz(possession(DefTeam)),
        retractall(cooldown(_)), assertz(cooldown(0)),
        bump(saves)
    ;
        score_goal(ScoringTeam)
    ).

score_goal(T) :-
    score(T, S), NS is S+1,
    retract(score(T,S)), assertz(score(T,NS)),
    retractall(carrier(_,_)), retractall(cooldown(_)), assertz(cooldown(0)),
    (NS >= 3 ->
        assertz(game_over(T))
    ;
        (T == team1 -> NextKO = team2 ; NextKO = team1),
        tick(Cur),
        PauseEnd is Cur + 120, ResetAt is Cur + 90,
        retractall(paused_until(_)),    assertz(paused_until(PauseEnd)),
        retractall(pending_reset(_,_)), assertz(pending_reset(NextKO, ResetAt)),
        retract(ball(_,_)), assertz(ball(pos(50,25), vel(0,0)))
    ).

% ------------------------------------------------------------------
% 10. MAIN STEP
% ------------------------------------------------------------------
step :-
    \+ game_over(_),
    tick(T), NT is T+1,
    retract(tick(T)), assertz(tick(NT)),
    (pending_reset(NextKO, ResetAt), NT >= ResetAt ->
        retractall(pending_reset(_,_)),
        reset_positions(NextKO)
    ; true),
    (paused_until(P), NT < P ->
        true
    ;
        run_ai,
        update_ball,
        tick_cooldown,
        try_pickup,
        process_goals
    ).

run_ai :-
    random(R),
    (R > 0.5 ->
        (ai_behavior(team1,forward), ai_behavior(team1,midfielder),
         ai_behavior(team1,defender), ai_behavior(team1,goalkeeper),
         ai_behavior(team2,forward), ai_behavior(team2,midfielder),
         ai_behavior(team2,defender), ai_behavior(team2,goalkeeper))
    ;
        (ai_behavior(team2,forward), ai_behavior(team2,midfielder),
         ai_behavior(team2,defender), ai_behavior(team2,goalkeeper),
         ai_behavior(team1,forward), ai_behavior(team1,midfielder),
         ai_behavior(team1,defender), ai_behavior(team1,goalkeeper))
    ).

% ------------------------------------------------------------------
% 11. STATE QUERY
% ------------------------------------------------------------------
get_all_state(BX, BY, Players, Score1, Score2, OT, OR, EvLabel) :-
    ball(pos(BX,BY), _),
    findall(p(T,R,X,Y,S,St), player(T,R,pos(X,Y),S,St), Players),
    score(team1, Score1), score(team2, Score2),
    (carrier(OT, OR) -> true ; OT = none, OR = none),
    EvLabel = none.

get_stats(Shots, Passes, Tackles, Saves) :-
    stat(shots, Shots), stat(passes, Passes),
    stat(tackles, Tackles), stat(saves, Saves).
