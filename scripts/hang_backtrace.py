"""lldb-Modul für scripts/hang-backtrace.sh: wartet, bis der angehängte Prozess steht (über WLAN dauert das),
gibt die Stacks aller Threads aus und löst sich wieder – ohne Detach würde lldb die App beim Beenden mitnehmen.
Liest die Stacks direkt über die SB-API (der Befehl `bt all` meldet direkt nach dem Anhängen noch „not stopped“)."""
import time

import lldb


def __lldb_init_module(debugger, _internal_dict):
    process = debugger.GetSelectedTarget().GetProcess()
    for _ in range(90):
        if process.GetState() == lldb.eStateStopped:
            break
        time.sleep(1)
    try:
        for thread in process:
            print(f"\nthread #{thread.GetIndexID()} {thread.GetQueueName() or ''} {thread.GetName() or ''}")
            for frame in thread:
                print(f"  {frame}")
    finally:
        process.Detach()
