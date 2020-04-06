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
        /// The name of the executing job.
        /// In order for the <see cref="SchedulerOptions"/> options to work correctly make sure that the name is matched
        /// between the job and the named job options.
        /// </summary>
        string Name { get; }

        /// <summary>
        /// Job that will be executing on this schedule.
        /// </summary>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        Task ExecuteAsync(CancellationToken cancellationToken);
    }
}
