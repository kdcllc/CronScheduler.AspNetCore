using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace CronSchedulerApp
{
#pragma warning disable RCS1102 // Make class static.
    public class Program
#pragma warning restore RCS1102 // Make class static.
    {
        public static void Main(string[] args)
        {
            CreateWebHostBuilder(args).Build().Run();
        }

        public static IWebHostBuilder CreateWebHostBuilder(string[] args)
        {
            return WebHost.CreateDefaultBuilder(args)
                    .ConfigureLogging((context, logger) =>
                    {
                        logger.AddConsole();
                        logger.AddDebug();
                        logger.AddConfiguration(context.Configuration.GetSection("Logging"));
                    })
                    .UseStartup<Startup>();
        }
    }
}
