using System;
using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.Extensions.Scheduler
{
    /// <summary>
    /// Forces the implementation of the required methods for the job.
    /// </summary>
    public interface IScheduledJob
    {
        /// <summary>
        /// Cron schedule.
        /// </summary>
        [Obsolete("This property will be remove from the interface in the next release. Please use" + nameof(SchedulerOptions.CronSchedule) + " instead.")]
        string CronSchedule { get; }

        /// <summary>
        /// When not specified the CronScheduler will use Local Time.
        /// </summary>
        [Obsolete("This property will be remove from the interface in the next release. Please use" + nameof(SchedulerOptions.CronTimeZone) + " instead.")]
        string CronTimeZone { get; }

        /// <summary>
        /// Should be run on application start.
        /// </summary>
        [Obsolete("This property will be remove from the interface in the next release. Please use" + nameof(SchedulerOptions.RunImmediately) + " instead.")]
        bool RunImmediately { get; }

        /// <summary>
        /// Job that will be executing on this schedule.
        /// </summary>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        Task ExecuteAsync(CancellationToken cancellationToken);
    }
}
