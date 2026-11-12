use sim::prelude::*;

#[test]
fn print_sizes() {
    println!("Hz {} GameSim {} SimState {} RoomRuntime {}", std::mem::size_of::<Hz>(), std::mem::size_of::<GameSim>(),
        std::mem::size_of::<SimState>(), std::mem::size_of::<RoomRuntime>());
    println!("ExitKey {} Lava {} BossCrusher {} Firework {} Block {} Crawler {} Pendulum {}", std::mem::size_of::<ExitKey>(), std::mem::size_of::<Lava>(),
        std::mem::size_of::<BossCrusher>(), std::mem::size_of::<Firework>(), std::mem::size_of::<Block>(), std::mem::size_of::<Crawler>(), std::mem::size_of::<Pendulum>());
}
