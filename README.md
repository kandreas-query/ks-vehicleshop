# Vehicle Shop

A simple vehicle shop resource for **QBCore** and **QBox**.

## Supported Frameworks

* [QBCore](https://github.com/qbcore-framework/qb-core)
* [QBox](https://github.com/Qbox-project/qbx_core)

## Dependencies

* `qb-core` or `qbx_core`
* [`ox_lib`](https://github.com/overextended/ox_lib)

## Installation

1. Download or clone the resource into your server's `resources` folder.

2. Make sure the required dependencies are installed and started.

3. Check config.lua.

4. Add the resource to your `server.cfg`:

```cfg
ensure ox_lib
ensure qb-core
ensure ks-vehicleshop
```

For QBox:

```cfg
ensure ox_lib
ensure qbx_core
ensure ks-vehicleshop
```

## Requirements

You only need **one** supported framework:

* `qb-core`
* `qbx_core`

`ox_lib` is hard dependency regardless of which framework you use.

## Usage
- Players: walk to a marker + **E** (no catalog command; locations show as blips; catalog or debt screen opens by marker type)
- Admin: `/adminvehicleshop` — location-independent NUI (vehicles, categories, markers/locations, finance settings, general settings, no restart)
- **Finance:** down % + max term (config + admin menu), interval/fee/repo limit (config); auto-charge by playtime; pay + reclaim at the debt office

![Screenshot](screenshot/1.png)
![Screenshot](screenshot/2.png)
