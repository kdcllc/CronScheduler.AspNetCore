using System.Threading;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    /// <summary>
    /// Forces the implementation of the required methods for the job.
    /// </summary>
    public interface IScheduledJob
    {
        /// <summary>
        /// Cron schedule.
        /// </summary>
        string CronSchedule { get; }

        /// <summary>
        /// Should be run on application start.
        /// </summary>
        bool RunImmediately { get; }

        /// <summary>
        /// Job that will be executing on this schedule.
        /// </summary>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        Task ExecuteAsync(CancellationToken cancellationToken);
    }
}
