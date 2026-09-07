namespace CronScheduler.Extensions.Scheduler;

public class SchedulerOptions
{
    /// <summary>
    /// Specify the CRON schedule.
    /// Supports standard five-field expressions, optional seconds, macros, and Cronos special characters.
    /// <see href="https://github.com/HangfireIO/Cronos#cron-format">Cronos cron format</see>.
    /// </summary>
    public string CronSchedule { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the optional deterministic seed used by Cronos schedule jitter.
    /// Set this value when <see cref="CronSchedule"/> contains the <c>H</c> character or when
    /// using a macro whose execution time should be distributed across scheduler instances.
    /// </summary>
    public int? CronJitterSeed { get; set; }

    /// <summary>
    /// Time Zone for the Scheduler to run. Default is null, sets it to local time zone.
    /// Can be set to "Eastern Standard Time" or "Pacific Standard Time" etc.
    /// </summary>
    public string? CronTimeZone { get; set; }

    /// <summary>
    /// Specify if the Job to be run immediately. Default value is false.
    /// </summary>
    public bool RunImmediately { get; set; }

    /// <summary>
    /// The name of the job that this options is associated with.
    /// </summary>
    internal string JobName { get; set; } = string.Empty;
}
