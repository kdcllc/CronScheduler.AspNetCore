using System.Threading;
using System.Threading.Tasks;

using Microsoft.Extensions.Hosting;

namespace CronScheduler.Extensions.StartupInitializer
{
    /// <summary>
    /// Allows to run async jobs on Program.cs.
    /// </summary>
    public interface IStartupJob
    {
        /// <summary>
        /// Starts async job for <see cref="IHost"/>.
        /// </summary>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        Task ExecuteAsync(CancellationToken cancellationToken = default);
    }
}
