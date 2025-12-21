# nix-scpsl

Manage SCP:SL servers using nix.

This project is *heavily* inspired by
[nix-minecraft](https://github.com/Infinidoge/nix-minecraft).

## Installation

Only nix flakes are supported at this time.
Add the following input to your `flake.nix` like so:

```nix
{
  inputs = {
    # ...
    nix-scpsl.url = "github:nanoyaki/nix-scpsl";
    # Optionally:
    # nix-scpsl.inputs.nixpkgs.follows = "nixpkgs";
    # ...
  };
}
```

Then add the following in your system configuration:

```nix
{ inputs, ... }:

{
  imports = [ inputs.nix-scpsl.nixosModules.default ];
  nixpkgs.overlays = [ inputs.nix-scpsl.overlays.default ];
}
```

## Module

### services\.scpsl-server\.enable



Whether to enable declarative management of SCP:SL
servers\. When enabled, servers defined using
` services.scpsl-server.servers `
will be set up\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



### services\.scpsl-server\.package



The scpsl-server package to use\.



*Type:*
package



*Default:*
` pkgs.scpsl-server `



### services\.scpsl-server\.dataDir

The data directory containing the configuration files
and logs for all servers\.



*Type:*
absolute path



*Default:*
` "/srv/scpsl" `



### services\.scpsl-server\.eula



Whether to accept [Northwood Studios’ EULA](https://store\.steampowered\.com/eula/700330_eula_0)\.
This option must be set to ` true ` in order
to run any SCP:SL server\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



### services\.scpsl-server\.group



The group that has access to the server and
it’s files\. To attach to the tmux socket it is necessary
for the user to be part of this group\.



*Type:*
string



*Default:*
` "scpsl" `



### services\.scpsl-server\.openFirewall



Whether to open the ports of all servers defined
in ` services.scpsl-server.servers `\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



### services\.scpsl-server\.servers



The individual server configuration\. If the attribute of
` services.scpsl-server.servers.<name> ` is set
to an integer value it’s assumed to be the port the server
binds to\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `



### services\.scpsl-server\.servers\.\<name>\.enable



Whether to enable this server\.



*Type:*
boolean



*Default:*
` false `



*Example:*
` true `



### services\.scpsl-server\.servers\.\<name>\.adminSettings



The remote admin configuration\. See the
[Tech Support Public Wiki](https://techwiki\.scpslgame\.com/books/server-guides/page/3-remote-admin-config-setup) for more information\.



*Type:*
open submodule of (YAML 1\.1 value)



*Default:*
` { } `



### services\.scpsl-server\.servers\.\<name>\.adminSettings\.Members



A list of an a steam 64 id followed by
` @steam ` mapped to a role defined in
` services.scpsl-server.servers.<name>.adminSettings.Roles `\.
Use this option to give a user administrative priviledges\.



*Type:*
list of attribute set of string



*Default:*
` [ ] `



*Example:*
` [ { "someSteam64Id@steam" = "owner"; } ] `



### services\.scpsl-server\.servers\.\<name>\.adminSettings\.Roles



List of role names that users are allowed to be assigned to\.



*Type:*
list of string



*Default:*

```
[
  "owner"
  "admin"
  "moderator"
]
```



*Example:*
` [ "admin" ] `



### services\.scpsl-server\.servers\.\<name>\.autoStart



Whether to start this server on boot\.
If set to false, use ` systemctl start scpsl-server-<name> `
to start the server\.



*Type:*
boolean



*Default:*
` true `



*Example:*
` true `



### services\.scpsl-server\.servers\.\<name>\.settings



The gameplay configuration\. See the
[Tech Support Public Wiki](https://techwiki\.scpslgame\.com/books/server-guides/page/2-gameplay-config-setup) for more information\.



*Type:*
open submodule of (YAML 1\.1 value)



*Default:*
` { } `



### services\.scpsl-server\.servers\.\<name>\.settings\.port



The port for this server\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*
` 7777 `



*Example:*
` 7778 `



### services\.scpsl-server\.servers\.\<name>\.socketPath



Function from the server’s name to the path at which the server’s tmux socket is placed\.
Defaults to ` /run/scpsl/<name>.sock `\.



*Type:*
function that evaluates to a(n) absolute path



*Default:*
` name: "/run/scpsl/${name}.sock" `



*Example:*
` _: ${cfg.dataDir}/main-server.sock `



### services\.scpsl-server\.user



The user that runs and creates the servers\.



*Type:*
string



*Default:*
` "scpsl" `


