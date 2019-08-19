using System;

using Cronos;

namespace CronScheduler.AspNetCore
{
    internal class SchedulerTaskWrapper
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="SchedulerTaskWrapper"/> class.
        /// </summary>
        /// <param name="cronExpression"></param>
        /// <param name="scheduledJob"></param>
        /// <param name="nextRunTime"></param>
        public SchedulerTaskWrapper(
            CronExpression cronExpression,
            IScheduledJob scheduledJob,
            DateTime nextRunTime)
        {
            Schedule = cronExpression;
            ScheduledJob = scheduledJob;
            NextRunTime = nextRunTime;
        }

        public CronExpression Schedule { get; set; }

        public IScheduledJob ScheduledJob { get; set; }

        public DateTime LastRunTime { get; set; }

        public DateTime NextRunTime { get; set; }

        public void Increment()
        {
            LastRunTime = NextRunTime;
            NextRunTime = Schedule.GetNextOccurrence(NextRunTime).Value;
        }

        public bool ShouldRun(DateTime currentTime)
        {
            return NextRunTime < currentTime && LastRunTime != NextRunTime;
        }
    }
}
