namespace FastSim;

/// How long a playtest bot's run may last. Bots play longer than the game's
/// own cap (SimConfig.MAX_TICKS, 30 minutes, which replays and the server
/// use): 60 minutes, about 2 400 points, so strong bots are rarely cut off.
/// A run longer than SimConfig.MAX_TICKS cannot be replayed or rendered by
/// the game (Replay.simulate stops there), so run files keep the game's cap.
public static class BotCaps
{
    public const long RUN_CAP = 60 * 60 * SimConfig.TICKS_PER_SECOND;
}
