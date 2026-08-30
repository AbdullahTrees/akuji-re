#!/usr/bin/env python3
"""Check the frame loop, and the form wiring no behavioural test covers.

    python tools/frame_shape.py

WHY A SOURCE-SHAPE TEST

The defect this guards against was not a wrong value, it was a wrong PLACE.
Entity_UpdateAll sat inside the state dispatch, in the play arm only, so it did
not run on the title screen, during the opening, or while paused. Every
individual line was a faithful translation; the arrangement was not.

No behavioural self-test caught it, and it is worth being clear about why: all
thirteen passed both before and after the fix. They drive a session directly
and never exercise the frame loop's own structure, because that structure lives
in a TForm and needs a window. So the claim being made here - "this arm runs
before the entity update, that one after" - is a claim about arrangement, and
the test for it has to read the arrangement.

WHERE THE TABLE COMES FROM

Not from reading the code. From notes/trace_findings.md, which is a 20,304
frame capture of the real game:

    Entity_UpdateAll        20304 calls / 20304 frames   every state
    Events_SpawnNearCamera  14560 = 12347 (state 60) + 2213 (state 140)
    EventScript_Execute      2213 = every frame of state 140
    frame 1 order: Title_Init, Entity_UpdateAll, Title_MainMenu

That last line is what proves there are two dispatches rather than one: two
different state arms ran in a single frame with the entity update between
them, which a single switch cannot do.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GM = os.path.join(REPO, 'src', 'GmMain.pas')

# Which dispatch each state's arm belongs to, from the trace.
EXPECT_PRE = {'GS_TITLE_INIT', 'GS_STAGE_BEGIN', 'GS_PLAY', 'GS_STATE_140'}
EXPECT_POST = {'GS_TITLE_MENU', 'GS_PLAYER_INIT', 'GS_PLAY_ALT', 'GS_PLAY',
               'GS_STATE_140', 'GS_PAUSE', 'GS_ENDING', 'GS_QUIT'}


def body_of(text, name):
    start = text.index('procedure TFrm_main.%s;' % name)
    end = text.index('\nend;', text.index('case GameStateValue of', start))
    return text[start:end]


def arms(body):
    return set(re.findall(r'^\s{4}(GS_[A-Z0-9_]+)\s*[,:]', body, re.M))


def main():
    text = open(GM, encoding='utf-8').read()
    bad = []

    for name in ('DispatchPre', 'DispatchPost'):
        if 'procedure TFrm_main.%s;' % name not in text:
            print('FAIL: %s is gone - the dispatch has been merged back into '
                  'one, which puts the entity update inside it again' % name)
            return 1

    got_pre, got_post = arms(body_of(text, 'DispatchPre')), \
        arms(body_of(text, 'DispatchPost'))

    for label, got, want in (('DispatchPre', got_pre, EXPECT_PRE),
                             ('DispatchPost', got_post, EXPECT_POST)):
        for extra in sorted(got - want):
            bad.append('%s has an arm for %s, which the trace shows running '
                       'on the other side of the entity update'
                       % (label, extra))
        for missing in sorted(want - got):
            bad.append('%s has no arm for %s' % (label, missing))

    # The DIV-002 keyboard stand-ins must be one-frame values.
    #
    # FMoveX / FMoveY / FConfirm replace a Joy poll the original runs every
    # frame, so they have to be cleared every frame. They were cleared inside
    # the GS_TITLE_MENU arm instead, which handed them to whatever ran next:
    # Down-then-Z in the PAUSE menu left FMoveY = 1 and FConfirm = True, pause
    # RESET goes to the title, and the title menu's first Update moved its
    # cursor 0 -> 1 and confirmed CONTINUE in the same call. Reset loaded the
    # save. No behavioural test can see this - both units are correct on their
    # own and the leak lives in the form.
    idle_for_flags = text[text.index('procedure TFrm_main.AppIdle'):]
    idle_for_flags = idle_for_flags[:idle_for_flags.index('\nprocedure ')]
    idle_for_flags = re.sub(r'[{][^}]*[}]', ' ', idle_for_flags)
    for flag in ('FMoveY', 'FMoveX', 'FConfirm'):
        if not re.search(r'(?<![A-Za-z0-9_])%s\s*:=\s*(0|False)\s*;' % flag,
                         idle_for_flags):
            bad.append('AppIdle never clears %s - a keypress in one state '
                       'survives into the next, and pause RESET turns into '
                       'title CONTINUE' % flag)
    # The fader is FROZEN while paused. 0x00464D30 puts these two lines
    # adjacent, and the second one's guard is the point:
    #     if (*p_GameState == 0x82) PauseMenu_Update();
    #     if (*p_GameState != 0x82) FUN_0044DC70(fader);
    # Without it a room transition caught mid-fade runs to completion behind
    # the pause menu.
    if not re.search(r'if\s+GameStateValue\s*<>\s*GS_PAUSE\s+then\s*'
                     r'DDDD1\.TickFade', idle_for_flags):
        bad.append('AppIdle ticks the fader without excluding GS_PAUSE - the '
                   'original freezes the fade while the pause menu is up')

    # The frame loop's own pause entry, which is NOT FormKeyDown's. Button 2
    # with its latch, guarded against re-entry and against the options page.
    if 'EnterPause' not in idle_for_flags:
        bad.append('AppIdle never enters pause - only FormKeyDown does, so the '
                   'mapped pause button does nothing')
    else:
        for token in ('PAUSE_CANCEL_BUTTON', 'TSM_OPTIONS', 'ButtonLatch'):
            if token not in idle_for_flags:
                bad.append('the AppIdle pause entry does not mention %s - the '
                           'original tests button 2 against its latch and '
                           'refuses on the title screen options page'
                           % token)

    post_body = re.sub(r'[{][^}]*[}]', ' ', body_of(text, 'DispatchPost'))
    for flag in ('FMoveY', 'FMoveX', 'FConfirm'):
        if re.search(r'(?<![A-Za-z0-9_])%s\s*:=\s*(0|False)\s*;' % flag, post_body):
            bad.append('DispatchPost clears %s inside a state arm - it must be '
                       'cleared once per FRAME, or the states that do not '
                       'clear it inherit it' % flag)

    # And the ordering in AppIdle: pre, then the entity update, then post.
    idle = text[text.index('procedure TFrm_main.AppIdle'):]
    idle = idle[:idle.index('\nprocedure ')]
    # Comments name the wrong thing on purpose, to say why it is wrong, so
    # strip them before matching - two checks here have now failed on
    # their own explanatory comments.
    idle_code = re.sub(r'[{][^}]*[}]', ' ', idle)
    order = [m.group(1) for m in re.finditer(
        r'\b(DispatchPre|FSession\.TickEntities|DispatchPost)\b', idle)]
    want_order = ['DispatchPre', 'FSession.TickEntities', 'DispatchPost']
    if order != want_order:
        bad.append('AppIdle calls %s; it must call %s, in that order - the '
                   'entity update goes BETWEEN the two dispatches'
                   % (' then '.join(order) or 'none of them',
                      ' then '.join(want_order)))

    # TickEntities must not be conditional. A guard here is the original bug
    # wearing a different hat.
    # idle_CODE, not idle. This check read the RAW text and so tripped on a
    # comment between the two dispatches that used the word `if` to explain
    # why the statement beside it is unconditional. That is the third check in
    # this file to fail on its own explanatory prose; the stripped copy exists
    # for exactly this and was simply not used here.
    seg = idle_code[idle_code.find('DispatchPre'):
                    idle_code.find('DispatchPost')]
    if re.search(r'(?<![A-Za-z0-9_])if(?![A-Za-z0-9_])', seg):
        bad.append('there is an `if` between DispatchPre and DispatchPost - '
                   'the entity update runs in EVERY state, unconditionally')

    # --- wiring that only a source check can see -------------------------
    #
    # Two real bugs lived here and no self-test could have caught either,
    # because both are about what GmMain CONNECTS rather than what any unit
    # computes. The units were correct and unreachable.
    #
    #   * GameStartOrLoad gates the whole of starting a game on Host.Opening,
    #     and GmMain passed a bare TStartHost whose Opening returns False
    #     unconditionally. The cutscene never ran; the story section simply did
    #     not appear. Opening.pas was right the whole time - the trace confirms
    #     its slide timings frame for frame.
    #   * PowerUp_Show's panel is dismissed by its fanfare ENDING. With no
    #     fanfare started, the dismiss test was applied to the looping stage
    #     music, which never stops, so collecting the dash orb softlocked.
    if 'TFormStartHost.Create(Self)' not in text:
        bad.append('GmMain is not passing a TFormStartHost - a bare TStartHost '
                   'returns False from Opening, so the cutscene never runs')
    # The SAME omission, twice: TStartHost has two do-nothing virtuals and both
    # were left unoverridden. Opening meant no cutscene; PlayMusic meant stage 1
    # ran in silence, because GameStartOrLoad starts the stage music through it.
    if 'procedure TFormStartHost.PlayMusic' not in text:
        bad.append('TFormStartHost does not override PlayMusic - '
                   'GameStartOrLoad starts the stage music through it and the '
                   'base class does nothing, so the stage plays in silence')
    # THE THIRD TIME. TSessionAudio's two methods are no-op defaults too, and
    # nothing overrode them, so event sub-op 9 (sound) and sub-op 12 (music)
    # both ran silently. The pattern is now the thing being guarded, not the
    # individual bugs: a base class whose defaults do nothing is invisible
    # until someone plays the game.
    if 'TFormAudio = class(TSessionAudio)' not in text:
        bad.append("there is no TFormAudio - the TSessionAudio defaults do "
                   'nothing, so event sounds and event music are silent')
    # Step 7. Player_Update's dash tests InputState[$10] = 0 AND AxisX <> 0,
    # which is only satisfiable if $10 - Moving - holds the PREVIOUS frame's
    # value. That means InputEndOfFrame has to run after the dispatch, not
    # before it. Setting Moving in PollInput made the two conditions
    # contradictory and the dash could never fire.
    if 'InputEndOfFrame' not in text:
        bad.append("nothing calls InputEndOfFrame - step 7. The dash tests "
                   "Moving = 0 AND AxisX <> 0, which only works if Moving is "
                   "the PREVIOUS frame's value")
    else:
        # Comment-stripped, like the clock check above - matching raw text
        # here picked up the arm table in AppIdle's own comment.
        order7 = [m.group(1) for m in re.finditer(
            r'(DispatchPost|InputStep7)', idle_code)]
        if order7 != ['DispatchPost', 'InputStep7']:
            bad.append("step 7 does not run after DispatchPost; the handlers "
                       "would read this frame's Moving instead of the "
                       "previous frame's")
    poll = text[text.index('procedure TFrm_main.PollInput;'):]
    poll = poll[:poll.index(chr(10) + 'end;')]
    poll_code = re.sub(r'[{][^}]*[}]', ' ', poll)
    if 'Moving' in poll_code or 'HoldTimer' in poll_code:
        bad.append('PollInput touches Moving or HoldTimer - both belong to '
                   'step 7, and doing them at poll time is what broke the dash')

    # EVERY TEventHost virtual must be overridden. This is the general form of
    # the check that was previously written one wiring at a time, by name,
    # after each was found - and it is what would have caught all seven of
    # them at once. A virtual with a do-nothing default is invisible until
    # someone plays the game.
    runner = open(os.path.join(REPO, 'src', 'EventRunner.pas'),
                  encoding='utf-8').read()
    k = runner.index('TEventHost = class')
    hostdecl = runner[k:runner.index('end;', k)]
    hosts = ''.join(open(os.path.join(REPO, 'src', f), encoding='utf-8').read()
                    for f in ('Dialogue.pas', 'GameSession.pas', 'GmMain.pas'))
    for m in sorted(set(re.findall(r'(?:procedure|function)\s+(\w+)', hostdecl))):
        # The parameter list can contain ';', so match through to `override`
        # rather than stopping at the first semicolon.
        if not re.search(r'(procedure|function)\s+%s[^A-Za-z0-9_].{0,200}?override\s*;' % m,
                         hosts, re.S):
            bad.append('TEventHost.%s is never overridden - its default does '
                       'nothing, so the event command silently has no effect' % m)

    if 'FDialogue.OnResumeMusic' not in text:
        bad.append('FDialogue.OnResumeMusic is not wired - Overlay_Update '
                   'restores the remembered track when the fanfare ends '
                   '(0x00450EF0), and without it the stage goes silent after '
                   'every power-up')
    if 'FSession.Audio := TFormAudio.Create' not in text:
        bad.append('TFormAudio exists but is not installed on the session')

    # The frame CLOCK. GetTickCount64 steps 15-16 ms on Windows, so reading it
    # here held the game to 40 fps against the original's 62. The original
    # reads timeGetTime, which is also the only one of the two that exists on
    # an XP target.
    if 'GetTickCount64' in idle_code:
        bad.append('AppIdle reads GetTickCount64 - it steps 15-16 ms on '
                   'Windows, which caps the frame rate near 40. The original '
                   'reads timeGetTime; use FrameClockMs')
    if 'FrameClockMs' not in idle_code:
        bad.append('AppIdle does not read FrameClockMs')
    if 'BeginFrameClock' not in text:
        bad.append('nothing calls BeginFrameClock - without timeBeginPeriod(1) '
                   'the Sleep(1) in AppIdle takes about 15.6 ms and caps the '
                   'frame rate anyway')
    for cb in ('FDialogue.OnSound', 'FDialogue.OnMusic',
               'FDialogue.OnRememberMusic'):
        if cb not in text:
            bad.append('%s is not wired - without the fanfare the power-up '
                       'panel has nothing to dismiss it' % cb)

    dlg = open(os.path.join(REPO, 'src', 'Dialogue.pas'), encoding='utf-8').read()
    seg = dlg[dlg.index('procedure TDialogueBox.SubMode'):]
    seg = seg[:seg.index(chr(10) + 'end;')]
    # Each is guarded by Assigned(X) and then CALLED, so the bare name appears
    # twice. Testing for the name alone is not enough: deleting the call leaves
    # the Assigned() guard behind and the check still passed - which it did,
    # under mutation, before this was tightened.
    for name, call in (('FOnSound', r'FOnSound\s*\('),
                       ('FOnRememberMusic', r'^\s*FOnRememberMusic\s*;'),
                       ('FOnMusic', r'FOnMusic\s*\(')):
        if not re.search(r'Assigned\s*\(\s*%s\s*\)' % name, seg) or            not re.search(call, seg, re.M):
            bad.append('TDialogueBox.SubMode does not guard AND call %s - '
                       'PowerUp_Show plays effect $10, REMEMBERS the current '
                       'track (0x00450EDC), then starts playlist entry 4; the '
                       'panel is dismissed by that track ending' % name)

    if bad:
        print('FAIL - the frame loop no longer matches the traced game:')
        for b in bad:
            print('  %s' % b)
        return 1

    print('frame loop OK - %d pre arms, %d post arms, entity update '
          'unconditional between them; opening and power-up audio wired'
          % (len(got_pre), len(got_post)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
