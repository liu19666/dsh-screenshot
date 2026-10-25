// Headless UI evidence mode (owner: overlay-dev).
//
// TryRun returns true when it handled the command line, so Program.Main can exit.
// Intended modes (see docs/INTERFACES.md):
//   --selftest <outDir>   render the overlay chrome + editor toolbar to PNG files
//   --auto <script> <outPng>  drive a scripted pointer path without real input
//   --detect <x,y> --json <path>  dump the detection result at a virtual point
public static class SelfTest
{
    public static bool TryRun(string[] args)
    {
        return false;
    }
}
