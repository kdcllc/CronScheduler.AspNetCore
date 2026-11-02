using System;

using Cronos;

using CronScheduler.Extensions.Scheduler;

namespace CronScheduler.Extensions.Internal;

public sealed class SchedulerTaskWrapper
{
    /// <summary>
    /// Initializes a new instance of the <see cref="SchedulerTaskWrapper"/> class.
    /// </summary>
    /// <param name="cronExpression"></param>
    /// <param name="scheduledJob"></param>
    /// <param name="nextRunTime"></param>
    /// <param name="timeZoneInfo"></param>
    public SchedulerTaskWrapper(
        CronExpression cronExpression,
        IScheduledJob scheduledJob,
        DateTimeOffset nextRunTime,
        TimeZoneInfo timeZoneInfo)
    {
        Schedule = cronExpression;
        ScheduledJob = scheduledJob;
        NextRunTime = nextRunTime;
        TimeZoneInfo = timeZoneInfo;
    }

    public CronExpression Schedule { get; set; }

    public IScheduledJob ScheduledJob { get; set; }

    public DateTimeOffset LastRunTime { get; set; }

    public DateTimeOffset NextRunTime { get; set; }

    public TimeZoneInfo TimeZoneInfo { get; set; }

    /// <summary>
    /// Gets the most recent occurrence before the specified instant.
    /// </summary>
    /// <param name="from">The instant from which to search backward.</param>
    /// <param name="inclusive">Whether an occurrence exactly at <paramref name="from"/> should be returned.</param>
    /// <returns>The previous occurrence in the scheduler's configured time zone, or <see langword="null"/> when none exists.</returns>
    public DateTimeOffset? GetPreviousOccurrence(DateTimeOffset from, bool inclusive = false)
    {
        return Schedule.GetPreviousOccurrence(from, TimeZoneInfo, inclusive);
    }

    public void Increment()
    {
        LastRunTime = NextRunTime;
        NextRunTime = Schedule.GetNextOccurrence(NextRunTime, TimeZoneInfo)!.Value;
    }

    public bool ShouldRun(DateTimeOffset currentTime)
    {
        return NextRunTime < currentTime && LastRunTime != NextRunTime;
    }
}
