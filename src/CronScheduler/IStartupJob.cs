using Microsoft.Extensions.Hosting;
using System.Threading.Tasks;

namespace CronScheduler.AspNetCore
{
    /// <summary>
    /// Allows to run async jobs on Program.cs.
    /// </summary>
    public interface IStartupJob
    {
        /// <summary>
        /// Starts async job for <see cref="IHost"/>.
        /// </summary>
        /// <returns></returns>
        Task StartAsync();
    }
}
