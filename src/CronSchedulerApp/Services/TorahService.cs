using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

using CronSchedulerApp.Jobs;

using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

using Newtonsoft.Json;

namespace CronSchedulerApp.Services
{
    /// <summary>
    /// <see cref="HttpClient"/> typed version of the service to access http://labs.bible.org/api_web_service.
    /// </summary>
    public class TorahService
    {
        private TorahQuoteJobOptions _options;

        /// <summary>
        /// Initializes a new instance of the <see cref="TorahService"/> class.
        /// </summary>
        /// <param name="httpClient"></param>
        /// <param name="options"></param>
        public TorahService(
            HttpClient httpClient,
            IOptionsMonitor<TorahQuoteJobOptions> options)
        {
            _options = options.Get(nameof(TorahQuoteJob));

            // updates on providers change
            options.OnChange((opt, n) =>
            {
                if (n == nameof(TorahQuoteJob))
                {
                    _options = opt;
                }
            });

            httpClient.DefaultRequestHeaders.Add("Accept", "application/json");
            httpClient.DefaultRequestHeaders.Add("User-Agent", nameof(TorahService));

            Client = httpClient;
        }

        public HttpClient Client { get; }

        /// <summary>
        /// Returns verses from the quotation.
        ///  Utilizes QqueryHelpers: https://rehansaeed.com/asp-net-core-hidden-gem-queryhelpers/.
        /// </summary>
        /// <param name="exp"></param>
        /// <param name="cancellationToken"></param>
        /// <returns></returns>
        public async Task<IList<TorahVerses>> GetVersesAsync(string exp, CancellationToken cancellationToken)
        {
            // create query parameters
            var args = new Dictionary<string, string>
            {
                { "type", "json" },
                { "passage", Uri.EscapeDataString(exp) }
            };

            var url = QueryHelpers.AddQueryString(_options.ApiUrl, args);

            using (var request = new HttpRequestMessage(HttpMethod.Get, url))
            {
                var response = await Client.SendAsync(request, cancellationToken).ConfigureAwait(false);
                response.EnsureSuccessStatusCode();

                var result = await response.Content.ReadAsStringAsync();
                return JsonConvert.DeserializeObject<List<TorahVerses>>(result);
            }
        }
    }
}
