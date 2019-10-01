# Migration

Version 2.0 introduced new package that supports generic `IHost` and doesn't have dependencies on `AspNetCore`.

## Packages changes

- `CronScheduler.Extensions` contains the basic generic code for Cron Scheduler.
- `CronScheduler.AspNetCore` contains specific extensions for `AspNetCore` hosting.

## Namespaces Changed

- `using CronScheduler.AspNetCore;` to `using CronScheduler.Extensions.Scheduler;`

- `using CronScheduler.AspNetCore;` to `using CronScheduler.Extensions.StartupInitializer`
