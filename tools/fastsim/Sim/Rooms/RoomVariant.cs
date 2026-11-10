namespace FastSim;

public sealed class RoomVariant
{
    public string id = "";
    public long spike_num = 1;
    public long spike_den = 1;
    public long extra_spikes = 0;
    public List<Func<Hazard>> hazards = new();

    public RoomVariant(string p_id = "") { id = p_id; }

    public RoomVariant sized(long num, long den, long p_extra_spikes)
    {
        spike_num = num;
        spike_den = den;
        extra_spikes = p_extra_spikes;
        return this;
    }

    public RoomVariant with(List<Func<Hazard>> p_hazards)
    {
        hazards = p_hazards;
        return this;
    }
}
